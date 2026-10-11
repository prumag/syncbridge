class StatusController < ActionController::Base
  layout "status"

  def show
    @attendee_count = Attendee.count
    @session_count = EventSession.count
    @speaker_count = Speaker.count
    @runs = SyncRun.recent.limit(20)
    @latest_by_resource = SyncRun::RESOURCES.index_with { |resource| SyncRun.recent.find_by(resource: resource) }
  end

  def run
    @run = SyncRun.find_by(id: params[:id])
    render plain: "Sync run not found", status: :not_found unless @run
  end
end
