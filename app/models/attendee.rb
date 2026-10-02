class Attendee < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
end
