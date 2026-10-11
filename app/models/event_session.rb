class EventSession < ApplicationRecord
  has_many :session_speakers, dependent: :destroy
  has_many :speakers, through: :session_speakers

  validates :external_id, presence: true, uniqueness: true
  validates :title, presence: true
end
