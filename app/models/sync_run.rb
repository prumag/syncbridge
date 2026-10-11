class SyncRun < ApplicationRecord
  # Speakers come first because sessions link to them.
  RESOURCES = %w[speakers attendees sessions].freeze
  STATUSES = %w[running succeeded failed].freeze

  validates :resource, inclusion: { in: RESOURCES }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def finish!(status:, error_message: nil)
    update!(status: status, error_message: error_message, finished_at: Time.current)
  end
end
