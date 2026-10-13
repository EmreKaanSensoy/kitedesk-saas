# frozen_string_literal: true

require "test_helper"

class TicketTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @agent = agents(:sarah)
    @base_time = Time.zone.parse("2026-10-15 09:00:00")
  end

  # ==============================================================
  # 1. SLA HESAPLAMA VE ÖNCELİK TESTLERİ
  # ==============================================================
  test "yeni bilet oluşturulduğunda önceliğe göre SLA sürelerini otomatik hesaplar" do
    travel_to @base_time do
      ticket = Ticket.create!(
        title: "Kritik Ödeme Hatası",
        description: "Müşteriler kart ile ödeme yapamıyor.",
        priority: "urgent",
        category: "Billing",
        requester_name: "Ali Vural",
        requester_email: "ali@example.com"
      )

      assert_equal "urgent", ticket.priority
      assert_equal "new_ticket", ticket.status
      assert_match(/^KD-\d{6}$/, ticket.ticket_number)

      # Acil (Urgent) SLA: İlk yanıt 1 saat, Çözüm 4 saat
      assert_equal @base_time + 1.hour, ticket.first_response_due_at
      assert_equal @base_time + 4.hours, ticket.resolution_due_at
      assert_not ticket.sla_breached?
    end
  end

  # ==============================================================
  # 2. DURUM GEÇİŞLERİ (STATE MACHINE) TESTLERİ
  # ==============================================================
  test "durum geçiş akışı kurallara uygun çalışır" do
    ticket = Ticket.create!(
      title: "Hesap Doğrulama",
      description: "E-posta doğrulama linki gelmedi.",
      priority: "medium",
      category: "Account",
      requester_name: "Ayşe Kaya",
      requester_email: "ayse@example.com"
    )

    # new_ticket -> open
    assert ticket.can_transition_to?("open")
    ticket.transition_to!("open", actor_name: @agent.name)
    assert_equal "open", ticket.status

    # open -> pending
    assert ticket.can_transition_to?("pending")
    ticket.transition_to!("pending", actor_name: @agent.name)
    assert_equal "pending", ticket.status

    # pending -> solved
    assert ticket.can_transition_to?("solved")
    ticket.transition_to!("solved", actor_name: @agent.name)
    assert_equal "solved", ticket.status
    assert_not_nil ticket.resolved_at

    # solved -> closed
    assert ticket.can_transition_to?("closed")
    ticket.transition_to!("closed", actor_name: "System")
    assert_equal "closed", ticket.status
    assert_not_nil ticket.closed_at

    # closed durumundan doğrudan geçişe izin verilmez (Zendesk standardı)
    assert_not ticket.can_transition_to?("open")
    assert_raises(StandardError) do
      ticket.transition_to!("open")
    end
  end

  # ==============================================================
  # 3. ZAMAN KURALI TESTİ 1: travel_to İLE İLK YANIT SLA AŞIMI
  # ==============================================================
  test "travel_to ile ilk yanıt SLA süresi aşıldığında bilet ihlale uğrar" do
    travel_to @base_time do
      ticket = Ticket.create!(
        title: "API Entegrasyon Sorunu",
        description: "Webhooklar 500 dönüyor.",
        priority: "urgent", # 1 saat SLA
        category: "Technical",
        requester_name: "Mehmet Can",
        requester_email: "mehmet@tech.com"
      )

      # 45 dakika sonra henüz ihlal yok
      travel 45.minutes
      ticket.check_sla_status!
      assert_not ticket.reload.sla_breached?

      # 65 dakika sonra (1 saati geçti) -> SLA aşılmalı!
      travel 20.minutes # Toplam 65 dakika
      ticket.check_sla_status!
      assert ticket.reload.sla_breached?
      assert_match(/İlk Yanıt/i, ticket.sla_breach_reason)
    end
  end

  # ==============================================================
  # 4. ZAMAN KURALI TESTİ 2: travel_to İLE 48 SAATLİK ÇÖZÜM OTOMATİK KAPATMA
  # ==============================================================
  test "travel_to ile çözülen bilet 48 saat sonra otomatik olarak closed durumuna geçer" do
    travel_to @base_time do
      ticket = Ticket.create!(
        title: "Kullanıcı Şifre Sıfırlama",
        description: "Şifremi unuttum.",
        priority: "low",
        category: "General",
        requester_name: "Selin Yılmaz",
        requester_email: "selin@example.com"
      )

      # Temsilci bileti çözüldü yaptı
      ticket.transition_to!("open")
      ticket.transition_to!("solved")
      assert_equal "solved", ticket.status

      # 24 saat sonra: Hâlâ solved olmalı, otomatik kapanmamalı
      travel 24.hours
      Ticket.auto_close_solved_tickets!
      assert_equal "solved", ticket.reload.status

      # 49 saat sonra: 48 saati geçtiği için otomatik CLOSED olmalı
      travel 25.hours # Toplam 49 saat
      closed_count = Ticket.auto_close_solved_tickets!
      assert_equal 1, closed_count
      assert_equal "closed", ticket.reload.status
      assert_not_nil ticket.closed_at
    end
  end

  # ==============================================================
  # 5. 100 PUANLIK TEST: KULLANILABİLİR PAS (GRATITUDE & OOO GUARD)
  # ==============================================================
  test "çözülmüş bilete teşekkür mesajı geldiğinde bilet OPEN durumuna düşmez ve SLA bozulmaz" do
    travel_to @base_time do
      ticket = Ticket.create!(
        title: "Fatura İndirme Problemi",
        description: "PDF fatura açılmıyor.",
        priority: "medium",
        category: "Billing",
        requester_name: "Emre Şensoy",
        requester_email: "emre@example.com"
      )

      ticket.transition_to!("open")
      ticket.transition_to!("solved")
      assert_equal "solved", ticket.status

      # Müşteri teşekkür etti
      msg = ticket.add_customer_message!("Harikasınız, sorun çözüldü çok teşekkürler!")

      assert msg.is_gratitude?
      assert ticket.reload.gratitude_loop_prevented?
      # Bilet yanlışlıkla OPEN durumuna dönmedi, SOLVED olarak kaldı!
      assert_equal "solved", ticket.status
      assert_not ticket.sla_breached?
    end
  end

  test "çözülmüş bilete gerçek bir devam sorunu geldiğinde bilet haklı olarak yeniden açılır" do
    travel_to @base_time do
      ticket = Ticket.create!(
        title: "VPN Bağlantı Hatası",
        description: "VPN kopuyor.",
        priority: "high",
        category: "Technical",
        requester_name: "Can Tekin",
        requester_email: "can@example.com"
      )

      ticket.transition_to!("open")
      ticket.transition_to!("solved")

      # Müşteri sorunun devam ettiğini belirtti
      msg = ticket.add_customer_message!("Maalesef hâlâ hata alıyorum, bağlanmıyor.")

      assert_not msg.is_gratitude?
      assert_equal "open", ticket.reload.status
    end
  end
end
