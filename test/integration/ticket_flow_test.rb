# frozen_string_literal: true

require "test_helper"

class TicketFlowTest < ActionDispatch::IntegrationTest
  setup do
    @ticket = tickets(:urgent_ticket)
    @agent = agents(:sarah)
  end

  test "ana sayfa ve bilet listesi düzgün yüklenir" do
    get tickets_path
    assert_response :success
    assert_select "h1, .kpi-title", minimum: 1
    assert_select "table.ticket-table"
  end

  test "bilet detay sayfası açılır ve SLA bilgileri görünür" do
    get ticket_path(@ticket)
    assert_response :success
    assert_select ".ticket-h1", text: @ticket.title
    assert_select ".sla-pill"
  end

  test "yeni bilet başarıyla açılır" do
    assert_difference("Ticket.count", 1) do
      post tickets_path, params: {
        ticket: {
          title: "Entegrasyon Auth Hatası",
          description: "OAuth2 yetkilendirme kodu süresi doluyor.",
          priority: "high",
          category: "Integration",
          requester_name: "Kerem Ak",
          requester_email: "kerem@example.com"
        }
      }
    end

    new_ticket = Ticket.last
    assert_redirected_to ticket_path(new_ticket)
    assert_equal "high", new_ticket.priority
    assert_equal "new_ticket", new_ticket.status
    assert_not_nil new_ticket.first_response_due_at
  end

  test "durum değişikliği başarıyla güncellenir" do
    patch update_status_ticket_path(@ticket), params: { new_status: "pending" }
    assert_redirected_to ticket_path(@ticket)
    assert_equal "pending", @ticket.reload.status
  end

  test "müşteri teşekkür yanıtı verdiğinde 100 puanlık Gratitude Guard devreye girer" do
    @ticket.update_columns(status: "solved", resolved_at: Time.current)

    post customer_reply_ticket_path(@ticket), params: {
      body: "Çok teşekkürler, sorun tamamen çözüldü elinize sağlık!"
    }

    assert_redirected_to ticket_path(@ticket)
    assert_equal "solved", @ticket.reload.status
    assert @ticket.gratitude_loop_prevented?
  end

  test "müşteri portalı ve sunum savunma sayfaları erişilebilir" do
    get customer_portal_tickets_path
    assert_response :success

    get presentation_defense_tickets_path
    assert_response :success
    assert_select "h1", text: /5 Dakikalık Canlı Tahta Sunumu/i
  end
end
