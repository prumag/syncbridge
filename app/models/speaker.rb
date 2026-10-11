class Speaker < ApplicationRecord
  has_many :session_speakers, dependent: :destroy
  has_many :event_sessions, through: :session_speakers

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
end
