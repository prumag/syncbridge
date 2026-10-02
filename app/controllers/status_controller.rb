class StatusController < ActionController::Base
  layout false

  def show
    @attendee_count = Attendee.count
    @session_count = EventSession.count
    @runs = SyncRun.recent.limit(20)
    @latest_by_resource = SyncRun::RESOURCES.index_with { |resource| SyncRun.recent.find_by(resource: resource) }
  end
end
