class FullSyncJob < ApplicationJob
  queue_as :default

  def perform(resource)
    FullSync.new(resource).call
  end
end
