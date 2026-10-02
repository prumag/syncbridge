require "test_helper"

class SyncRunsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "index lists recent runs newest first" do
    SyncRun.create!(resource: "attendees", status: "succeeded", records_fetched: 5)
    newest = SyncRun.create!(resource: "sessions", status: "failed", error_message: "boom")

    get sync_runs_url

    assert_response :success
    body = response.parsed_body
    assert_equal 2, body.size
    assert_equal newest.id, body.first["id"]
  end

  test "create enqueues a full sync job" do
    assert_enqueued_with(job: FullSyncJob, args: [ "attendees" ]) do
      post sync_runs_url, params: { resource: "attendees" }
    end

    assert_response :accepted
  end

  test "create rejects unknown resources" do
    assert_no_enqueued_jobs do
      post sync_runs_url, params: { resource: "invoices" }
    end

    assert_response :unprocessable_entity
  end
end
