# frozen_string_literal: true

class TicketsController < ApplicationController
  before_action :set_current_agent
  before_action :set_ticket, only: %i[show update_status update_priority assign add_message customer_reply reopen_issue simulate_time]

  def index
    # Keep SLAs actively refreshed
    Ticket.active.find_each(&:check_sla_status!)

    @total_count = Ticket.count
    @open_count = Ticket.where(status: %w[new_ticket open pending]).count
    @urgent_count = Ticket.where(priority: "urgent").where.not(status: "closed").count
    @breached_count = Ticket.where(sla_breached: true).where.not(status: "closed").count
    @gratitude_prevented_count = Ticket.where(gratitude_loop_prevented: true).count

    @tickets = Ticket.all.order(created_at: :desc)

    case params[:filter]
    when "unassigned"
      @tickets = @tickets.unassigned
    when "urgent"
      @tickets = @tickets.where(priority: "urgent")
    when "breached"
      @tickets = @tickets.where(sla_breached: true)
    when "solved"
      @tickets = @tickets.where(status: "solved")
    when "closed"
      @tickets = @tickets.where(status: "closed")
    when "gratitude"
      @tickets = @tickets.where(gratitude_loop_prevented: true)
    end

    if params[:category].present?
      @tickets = @tickets.where(category: params[:category])
    end

    if params[:q].present?
      q = "%#{params[:q]}%"
      @tickets = @tickets.where("title LIKE ? OR requester_name LIKE ? OR ticket_number LIKE ?", q, q, q)
    end
  end

  def show
    @ticket.check_sla_status!
    @messages = @ticket.ticket_messages.order(created_at: :asc)
    @events = @ticket.ticket_events.order(created_at: :desc)
    @agents = Agent.active
  end

  def new
    @ticket = Ticket.new
  end

  def create
    @ticket = Ticket.new(ticket_params)

    if @ticket.save
      redirect_to ticket_path(@ticket), notice: "Destek bileti (#{@ticket.ticket_number}) başarıyla oluşturuldu! SLA hedefleri başlatıldı."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update_status
    new_status = params[:new_status]
    begin
      @ticket.transition_to!(new_status, actor_name: @current_agent.name, reason: params[:reason])
      redirect_to ticket_path(@ticket), notice: "Bilet durumu '#{new_status.upcase}' olarak güncellendi."
    rescue StandardError => e
      redirect_to ticket_path(@ticket), alert: e.message
    end
  end

  def update_priority
    new_priority = params[:priority]
    @ticket.recalculate_slas_for_priority!(new_priority, actor_name: @current_agent.name)
    redirect_to ticket_path(@ticket), notice: "Öncelik '#{new_priority.upcase}' olarak değiştirildi ve SLA hedefleri yeniden hesaplandı."
  end

  def assign
    agent = Agent.find(params[:agent_id])
    @ticket.assign_to!(agent, actor_name: @current_agent.name)
    redirect_to ticket_path(@ticket), notice: "Bilet başarıyla #{agent.name} isimli temsilciye atandı."
  end

  def add_message
    body = params[:body]
    is_internal = params[:is_internal_note] == "1"

    if body.blank?
      redirect_to ticket_path(@ticket), alert: "Mesaj alanı boş bırakılamaz."
      return
    end

    @ticket.add_agent_message!(body, agent: @current_agent, is_internal_note: is_internal)
    redirect_to ticket_path(@ticket), notice: is_internal ? "Dahili not eklendi (müşteri görmez)." : "Yanıt müşteriye iletildi ve ilk yanıt kaydedildi."
  end

  def customer_reply
    body = params[:body]
    if body.blank?
      redirect_to ticket_path(@ticket), alert: "Mesaj alanı boş bırakılamaz."
      return
    end

    msg = @ticket.add_customer_message!(body, sender_name: @ticket.requester_name, sender_email: @ticket.requester_email)

    if msg.is_gratitude?
      redirect_to ticket_path(@ticket), notice: "🛡️ [100 PUAN ÖZELLİĞİ AKTİF]: Müşterinin teşekkür/tatil mesajı tespit edildi. Bilet SOLVED durumunda tutuldu, destek kuyruğu kirletilmedi!"
    else
      redirect_to ticket_path(@ticket), notice: "Müşteri yanıtı eklendi. Bilet durumu 'OPEN' olarak güncellendi."
    end
  end

  def reopen_issue
    if @ticket.status == "solved"
      @ticket.transition_to!("open", actor_name: @ticket.requester_name, reason: "Müşteri 'Hala yardıma ihtiyacım var' butonuna tıkladı.")
      redirect_to ticket_path(@ticket), notice: "Bilet talebiniz üzerine yeniden açıldı (OPEN)."
    else
      redirect_to ticket_path(@ticket), alert: "Yalnızca çözülmüş (SOLVED) biletler bu şekilde yeniden açılabilir."
    end
  end

  # ==========================================
  # CANLI SUNUM SİMÜLASYON YARDIMCILARI
  # (Canlı sınıfta 5 dakikalık sunumu 2 saniyede kanıtlamak için)
  # ==========================================

  def simulate_time
    action_type = params[:sim_action]

    case action_type
    when "expire_first_response"
      # İlk yanıt SLA süresini geriye çekerek ihlale uğrat
      @ticket.update_columns(
        created_at: 5.hours.ago,
        first_response_due_at: 1.hour.ago,
        sla_breached: true,
        sla_breach_reason: "İlk Yanıt SLA Süresi Aşıldı (Simüle Edildi)"
      )
      @ticket.ticket_events.create!(
        event_type: "sla_breached",
        actor_name: "Canlı Sunum Simülatörü",
        details: "İlk yanıt SLA süresi yapay olarak geriye sarıldı; SLA ihlali tetiklendi."
      )
      redirect_to ticket_path(@ticket), notice: "⏱️ Canlı Sunum: İlk yanıt SLA süresi geriye çekildi, SLA İHLAL EDİLDİ!"

    when "expire_48h_resolution"
      # Çözülmüş bileti 50 saat öncesine al
      @ticket.update_columns(
        status: "solved",
        resolved_at: 50.hours.ago
      )
      @ticket.ticket_events.create!(
        event_type: "status_changed",
        actor_name: "Canlı Sunum Simülatörü",
        details: "Çözüm zamanı 50 saat öncesine alındı (48 saatlik otomatik kapatma tetiklenmeye hazır)."
      )
      redirect_to ticket_path(@ticket), notice: "⏱️ Canlı Sunum: Bilet çözülme zamanı 50 saat öncesi yapıldı. Şimdi '48 Saatlik Kapatmayı Çalıştır' diyebilirsiniz."

    when "run_auto_close_single"
      if @ticket.status == "solved" && @ticket.resolved_at.present? && @ticket.resolved_at <= 48.hours.ago
        @ticket.transition_to!("closed", actor_name: "Auto-Close Engine", reason: "48 saatlik hareketsizlik kuralı tetiklendi.")
        redirect_to ticket_path(@ticket), notice: "✅ Bilet 48 saatlik süre kuralı ile otomatik olarak CLOSED durumuna geçti!"
      else
        redirect_to ticket_path(@ticket), alert: "Bu bilet henüz 48 saati doldurmadı veya solved durumunda değil."
      end

    when "reset_slas"
      @ticket.update_columns(
        first_responded_at: nil,
        resolved_at: nil,
        closed_at: nil,
        sla_breached: false,
        sla_breach_reason: nil,
        gratitude_loop_prevented: false,
        created_at: Time.current
      )
      @ticket.calculate_initial_slas(Time.current)
      @ticket.save!
      redirect_to ticket_path(@ticket), notice: "SLA süreleri ve ihlaller sıfırlandı."
    else
      redirect_to ticket_path(@ticket), alert: "Bilinmeyen simülasyon işlemi."
    end
  end

  def run_auto_close
    count = Ticket.auto_close_solved_tickets!
    redirect_to tickets_path, notice: "Otomatik kapatma motoru çalıştırıldı: #{count} adet 48 saati aşmış çözülmüş bilet 'CLOSED' yapıldı."
  end

  def reset_seed_data
    Rails.application.load_seed
    redirect_to tickets_path, notice: "Tüm demo ve test verileri başarıyla ilk hâline sıfırlandı!"
  end

  def customer_portal
    @tickets = Ticket.all.order(created_at: :desc)
    @new_ticket = Ticket.new
  end

  def presentation_defense
    # Live defense cheat sheet for the student
  end

  private

  def set_current_agent
    if params[:switch_agent_id].present?
      session[:agent_id] = params[:switch_agent_id]
    end

    @current_agent = Agent.find_by(id: session[:agent_id]) || Agent.first
  end

  def set_ticket
    @ticket = Ticket.find(params[:id])
  end

  def ticket_params
    params.require(:ticket).permit(:title, :description, :priority, :category, :requester_name, :requester_email)
  end
end
