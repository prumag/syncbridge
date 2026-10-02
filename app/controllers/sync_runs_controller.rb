class SyncRunsController < ApplicationController
  def index
    runs = SyncRun.recent.limit(50)
    render json: runs.map { |run| serialize(run) }
  end

  def create
    resource = params.require(:resource)
    return render(json: { error: "unknown resource" }, status: :unprocessable_entity) unless SyncRun::RESOURCES.include?(resource)

    FullSyncJob.perform_later(resource)
    render json: { status: "enqueued", resource: resource }, status: :accepted
  end

  private

  def serialize(run)
    run.as_json(only: %i[id resource status started_at finished_at records_fetched records_created records_updated error_message])
  end
end
