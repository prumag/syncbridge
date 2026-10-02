class AttendeesController < ApplicationController
  def index
    render json: {
      total: Attendee.count,
      data: Attendee.order(:id).limit(100).as_json(only: %i[id external_id name email company external_updated_at])
    }
  end
end
