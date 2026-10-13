# frozen_string_literal: true

puts "== Seeding KiteDesk Enterprise Helpdesk =="

TicketEvent.destroy_all
TicketMessage.destroy_all
Ticket.destroy_all
Agent.destroy_all

# 1. Create Support Agents
sarah = Agent.create!(
  name: "Sarah Connor",
  email: "sarah.connor@kitedesk.io",
  role: "Principal Support Lead",
  avatar_color: "#6366f1", # Indigo
  active: true
)

alex = Agent.create!(
  name: "Alex Mercer",
  email: "alex.mercer@kitedesk.io",
  role: "Enterprise Support Engineer",
  avatar_color: "#0ea5e9", # Sky Blue
  active: true
)

elena = Agent.create!(
  name: "Elena Rostova",
  email: "elena.rostova@kitedesk.io",
  role: "Tier 2 Technical Specialist",
  avatar_color: "#10b981", # Emerald
  active: true
)

puts "Created #{Agent.count} agents."

# 2. Ticket 1: Urgent - Production Latency Spike (Active Open)
t1 = Ticket.create!(
  title: "Production API Gateway 504 Gateway Timeout Spikes",
  description: "B2B checkout clients are experiencing 504 gateway timeout errors on /v2/payments endpoint during European peak traffic.",
  priority: "urgent",
  status: "open",
  category: "Technical",
  requester_name: "Marc Andreessen",
  requester_email: "marc@enterprise-fintech.com",
  agent: sarah
)
t1.add_customer_message!("Here is the curl trace showing 15s timeout: curl -X POST https://api.kitedesk.io/v2/payments -d {...}")
t1.add_agent_message!("Investigating ingress gateway pod autoscaling right now. SRE team notified.", agent: sarah, is_internal_note: true)
t1.add_agent_message!("Hello Marc, our SRE team has scaled the gateway replicas and latency is stabilizing. We are monitoring.", agent: sarah, is_internal_note: false)

# 3. Ticket 2: High - SLA Breached Demo Ticket (First Response SLA Breached)
t2 = Ticket.create!(
  title: "SSO SAML Assertion Failure for Enterprise Workspace",
  description: "Our 4,000 corporate users cannot log in via Okta SAML 2.0 integration. Error: 'Invalid Signature'.",
  priority: "high",
  status: "new_ticket",
  category: "Security",
  requester_name: "Jennifer Sterling",
  requester_email: "jennifer.s@globalcorp.net",
  created_at: 6.hours.ago,
  first_response_due_at: 2.hours.ago,
  resolution_due_at: 6.hours.from_now,
  sla_breached: true,
  sla_breach_reason: "İlk Yanıt SLA Süresi Aşıldı (First Response SLA Breached)"
)
t2.ticket_events.create!(
  event_type: "sla_breached",
  actor_name: "SLA Watchdog",
  details: "İlk yanıt hedef süresi aşıldı (2 saat önce)",
  created_at: 2.hours.ago
)

# 4. Ticket 3: 100-Point Differentiator Demo (Solved + Gratitude Guard Intercepted!)
t3 = Ticket.create!(
  title: "Monthly Invoice Missing Tax Exemption Certificate",
  description: "Please attach our verified 2026 VAT tax exemption certificate to the September invoice.",
  priority: "medium",
  status: "solved",
  category: "Billing",
  requester_name: "Kaan Yılmaz",
  requester_email: "kaan@techlogistics.com",
  agent: alex,
  resolved_at: 2.hours.ago
)
t3.add_agent_message!("Hi Kaan, I have updated the invoice with your 2026 exemption certificate and re-issued the PDF. You can download it directly from your billing portal.", agent: alex, is_internal_note: false)
# Customer replied with pure gratitude:
t3.add_customer_message!("Harikasınız, faturayı indirdim sorun çözüldü çok teşekkür ederim!")

# 5. Ticket 4: Pending Customer Response
t4 = Ticket.create!(
  title: "Webhook delivery failure on custom port 8443",
  description: "Custom endpoint webhooks are not arriving at our staging server.",
  priority: "medium",
  status: "pending",
  category: "Integration",
  requester_name: "Liam O'Connor",
  requester_email: "liam@finflow.io",
  agent: elena
)
t4.add_agent_message!("Hi Liam, could you verify if port 8443 is exposed through your AWS security group? We received connection refused.", agent: elena, is_internal_note: false)

# 6. Ticket 5: 48-Hour Solved Ticket (Ready for Auto-Close Demo)
t5 = Ticket.create!(
  title: "User Seat Deallocation Request",
  description: "Please revoke license for departed employee and issue credit.",
  priority: "low",
  status: "solved",
  category: "Account",
  requester_name: "Rachel Green",
  requester_email: "rachel@ralphlauren.com",
  agent: alex,
  created_at: 55.hours.ago,
  resolved_at: 50.hours.ago
)
t5.add_agent_message!("The user seat has been deallocated and pro-rated credit applied to your next cycle.", agent: alex, is_internal_note: false)

puts "Seeded #{Ticket.count} sample enterprise tickets."
