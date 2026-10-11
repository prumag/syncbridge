class SessionSpeaker < ApplicationRecord
  belongs_to :event_session
  belongs_to :speaker

  validates :speaker_id, uniqueness: { scope: :event_session_id }
end
