# frozen_string_literal: true

class TicketEvent < ApplicationRecord
  belongs_to :ticket

  validates :event_type, presence: true
  validates :details, presence: true

  EVENT_TYPES = %w[
    created
    status_changed
    assigned
    priority_changed
    first_response_recorded
    sla_breached
    gratitude_intercepted
    reopened
    auto_closed
  ].freeze
end
