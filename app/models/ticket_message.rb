# frozen_string_literal: true

class TicketMessage < ApplicationRecord
  belongs_to :ticket

  validates :body, presence: true
  validates :sender_name, presence: true
  validates :sender_type, inclusion: { in: %w[customer agent system] }

  scope :public_messages, -> { where(is_internal_note: false) }
  scope :internal_notes, -> { where(is_internal_note: true) }

  def customer?
    sender_type == "customer"
  end

  def agent?
    sender_type == "agent"
  end

  def system?
    sender_type == "system"
  end
end
