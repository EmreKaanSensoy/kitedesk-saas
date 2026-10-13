# frozen_string_literal: true

class Agent < ApplicationRecord
  has_many :tickets, dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true

  scope :active, -> { where(active: true) }

  def initials
    name.split.map(&:first).join.upcase[0..1]
  end

  def open_tickets_count
    tickets.where.not(status: %w[solved closed]).count
  end
end
