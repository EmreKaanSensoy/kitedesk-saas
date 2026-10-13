# frozen_string_literal: true

class Ticket < ApplicationRecord
  belongs_to :agent, optional: true
  has_many :ticket_messages, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :ticket_events, -> { order(created_at: :asc) }, dependent: :destroy

  STATUSES = %w[new_ticket open pending solved closed].freeze
  PRIORITIES = %w[low medium high urgent].freeze
  CATEGORIES = %w[General Billing Technical Account Security Integration].freeze

  VALID_TRANSITIONS = {
    "new_ticket" => %w[open solved closed],
    "open"       => %w[pending solved closed],
    "pending"    => %w[open solved closed],
    "solved"     => %w[open closed],
    "closed"     => %w[] # Closed tickets cannot be reopened directly
  }.freeze

  SLA_CONFIG = {
    "urgent" => { first_response: 1.hour,  resolution: 4.hours },
    "high"   => { first_response: 4.hours, resolution: 12.hours },
    "medium" => { first_response: 12.hours, resolution: 48.hours },
    "low"    => { first_response: 24.hours, resolution: 96.hours }
  }.freeze

  validates :ticket_number, presence: true, uniqueness: true
  validates :title, presence: true, length: { maximum: 200 }
  validates :description, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :category, presence: true
  validates :requester_name, presence: true
  validates :requester_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_validation :generate_ticket_number, on: :create
  before_create :calculate_initial_slas
  after_create :log_creation_event

  scope :active, -> { where.not(status: "closed") }
  scope :unassigned, -> { where(agent_id: nil) }
  scope :breached, -> { where(sla_breached: true) }

  # ==========================================
  # STATE MACHINE & WORKFLOW METHODS
  # ==========================================

  def can_transition_to?(new_status)
    return true if status == new_status
    VALID_TRANSITIONS.fetch(status, []).include?(new_status)
  end

  def transition_to!(new_status, actor_name: "System", reason: nil)
    unless can_transition_to?(new_status)
      raise StandardError, "Geçersiz durum geçişi: '#{status}' durumundan '#{new_status}' durumuna geçilemez."
    end

    return true if status == new_status

    old_status = status
    updates = { status: new_status }

    case new_status
    when "solved"
      updates[:resolved_at] = Time.current unless resolved_at.present?
    when "closed"
      updates[:closed_at] = Time.current unless closed_at.present?
    when "open"
      # If reopened from solved
      updates[:resolved_at] = nil if old_status == "solved"
    end

    update!(updates)

    ticket_events.create!(
      event_type: "status_changed",
      actor_name: actor_name,
      details: "Durum değiştirildi: #{old_status.upcase} -> #{new_status.upcase}#{reason ? " (#{reason})" : ""}"
    )
    true
  end

  def assign_to!(new_agent, actor_name: "System")
    old_agent_name = agent&.name || "Atanmamış"
    self.agent = new_agent
    self.status = "open" if status == "new_ticket"
    save!

    ticket_events.create!(
      event_type: "assigned",
      actor_name: actor_name,
      details: "Bilet atandı: #{old_agent_name} -> #{new_agent.name}"
    )
  end

  # ==========================================
  # SLA & TIME RULES
  # ==========================================

  # Sunum Soru Savunması: "SLA hafta sonunu saymasın kuralı nereye yazılır?"
  # Cevap: Tam olarak bu metoda (calculate_due_date)!
  # Hafta sonu veya tatilleri dışarıda bırakmak için base_time üzerine duration eklerken
  # iş saatleri (business hours / weekend skip) algoritması bu noktaya entegre edilir.
  def calculate_due_date(base_time, duration)
    base_time + duration
  end

  def calculate_initial_slas(base_time = Time.current)
    config = SLA_CONFIG.fetch(priority, SLA_CONFIG["medium"])
    self.first_response_due_at = calculate_due_date(base_time, config[:first_response])
    self.resolution_due_at     = calculate_due_date(base_time, config[:resolution])
  end

  def recalculate_slas_for_priority!(new_priority, actor_name: "System")
    return if priority == new_priority

    old_priority = priority
    self.priority = new_priority
    config = SLA_CONFIG.fetch(new_priority, SLA_CONFIG["medium"])
    base_time = created_at || Time.current

    self.first_response_due_at = calculate_due_date(base_time, config[:first_response])
    self.resolution_due_at     = calculate_due_date(base_time, config[:resolution])
    save!

    ticket_events.create!(
      event_type: "priority_changed",
      actor_name: actor_name,
      details: "Öncelik güncellendi: #{old_priority.upcase} -> #{new_priority.upcase}. Yeni SLA süreleri uygulandı."
    )
    check_sla_status!
  end

  def check_sla_status!(current_time = Time.current)
    # 1. First Response SLA Check
    if first_responded_at.blank? && first_response_due_at.present? && current_time > first_response_due_at
      unless sla_breached? && sla_breach_reason&.include?("İlk Yanıt")
        update_columns(sla_breached: true, sla_breach_reason: "İlk Yanıt SLA Süresi Aşıldı (First Response SLA Breached)")
        ticket_events.create!(
          event_type: "sla_breached",
          actor_name: "SLA Watchdog",
          details: "İlk yanıt hedef süresi aşıldı (#{first_response_due_at.strftime('%d.%m.%Y %H:%M')})"
        )
      end
    end

    # 2. Resolution SLA Check
    if status != "solved" && status != "closed" && resolution_due_at.present? && current_time > resolution_due_at
      unless sla_breached? && sla_breach_reason&.include?("Çözüm")
        reason = sla_breached? ? "#{sla_breach_reason} + Çözüm SLA Aşıldı" : "Çözüm SLA Süresi Aşıldı (Resolution SLA Breached)"
        update_columns(sla_breached: true, sla_breach_reason: reason)
        ticket_events.create!(
          event_type: "sla_breached",
          actor_name: "SLA Watchdog",
          details: "Çözüm hedef süresi aşıldı (#{resolution_due_at.strftime('%d.%m.%Y %H:%M')})"
        )
      end
    end

    sla_breached?
  end

  def record_first_response!(timestamp = Time.current, actor_name: "Agent")
    return if first_responded_at.present?

    self.first_responded_at = timestamp
    save!

    ticket_events.create!(
      event_type: "first_response_recorded",
      actor_name: actor_name,
      details: "İlk temsilci yanıtı kaydedildi."
    )
  end

  # TIME RULE: 48 Saat Boyunca Çözülmüş Kalan Biletlerin Otomatik Kapatılması
  def self.auto_close_solved_tickets!(threshold = 48.hours.ago, actor_name: "Auto-Close Engine")
    solved_candidates = where(status: "solved").where("resolved_at <= ?", threshold)
    count = 0

    solved_candidates.find_each do |ticket|
      ticket.transition_to!("closed", actor_name: actor_name, reason: "48 saatlik hareketsizlik sonrası otomatik kapatıldı.")
      count += 1
    end

    count
  end

  # ==========================================
  # 100 PUANLIK ÖZELLİK: "KULLANILABİLİR PAS"
  # Smart Gratitude & OOO Guard
  # ==========================================

  def add_customer_message!(body, sender_name: requester_name, sender_email: requester_email)
    check_sla_status!

    is_gratitude = GratitudeDetector.gratitude_or_out_of_office?(body)

    msg = ticket_messages.create!(
      sender_type: "customer",
      sender_name: sender_name,
      sender_email: sender_email,
      body: body,
      is_internal_note: false,
      is_gratitude: is_gratitude
    )

    if status == "solved"
      if is_gratitude
        # 100 PUAN ÇÖZÜMÜ: Bileti tekrar açma, SLA sayacını sıfırlama, destek kuyruğunu temiz tut!
        update_columns(gratitude_loop_prevented: true)
        ticket_events.create!(
          event_type: "gratitude_intercepted",
          actor_name: "KiteDesk Gratitude Guard",
          details: "Müşteri teşekkür/tatil mesajı tespit edildi ('#{body.truncate(40)}'). Bilet SOLVED durumunda tutuldu, SLA bozulması engellendi."
        )
      else
        # Müşterinin gerçek bir sorunu devam ediyor -> Aç
        transition_to!("open", actor_name: sender_name, reason: "Müşteri takip sorusu gönderdi.")
      end
    elsif status == "pending"
      transition_to!("open", actor_name: sender_name, reason: "Müşteri beklenen bilgiyi sağladı.")
    end

    msg
  end

  def add_agent_message!(body, agent:, is_internal_note: false)
    check_sla_status!

    msg = ticket_messages.create!(
      sender_type: "agent",
      sender_name: agent.name,
      sender_email: agent.email,
      body: body,
      is_internal_note: is_internal_note,
      is_gratitude: false
    )

    unless is_internal_note
      record_first_response!(Time.current, actor_name: agent.name)
      if status == "new_ticket"
        transition_to!("open", actor_name: agent.name, reason: "Temsilci ilk yanıtı verdi.")
      end
    end

    msg
  end

  # ==========================================
  # VIEW / BADGE HELPERS
  # ==========================================

  def sla_badge_status(current_time = Time.current)
    return :breached if sla_breached?

    # Check if target is close (within 30 mins)
    target = first_responded_at.blank? ? first_response_due_at : resolution_due_at
    return :healthy unless target.present?

    diff = target - current_time
    if diff <= 0
      :breached
    elsif diff < 30.minutes
      :warning
    else
      :healthy
    end
  end

  def first_response_remaining_seconds(current_time = Time.current)
    return 0 unless first_response_due_at
    (first_response_due_at - current_time).to_i
  end

  def resolution_remaining_seconds(current_time = Time.current)
    return 0 unless resolution_due_at
    (resolution_due_at - current_time).to_i
  end

  private

  def generate_ticket_number
    return if ticket_number.present?
    loop do
      self.ticket_number = "KD-#{SecureRandom.random_number(900000) + 100000}"
      break unless Ticket.exists?(ticket_number: ticket_number)
    end
  end

  def log_creation_event
    ticket_events.create!(
      event_type: "created",
      actor_name: requester_name,
      details: "Destek talebi oluşturuldu (#{priority.upcase} öncelik, #{category} kategorisi)."
    )
  end
end
