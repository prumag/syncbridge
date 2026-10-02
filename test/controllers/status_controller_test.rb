require "test_helper"

class StatusControllerTest < ActionDispatch::IntegrationTest
  test "shows an empty state when nothing has synced" do
    get root_url

    assert_response :success
    assert_includes response.body, "No syncs yet"
    assert_includes response.body, "Never"
  end

  test "offers a sync button per resource" do
    get root_url

    assert_select "button.sync-button[data-resource=attendees]:not([disabled])"
    assert_select "button.sync-button[data-resource=sessions]:not([disabled])"
  end

  test "disables the button for a resource that is already syncing" do
    SyncRun.create!(resource: "sessions", status: "running", started_at: Time.current)

    get root_url

    assert_select "button.sync-button[data-resource=sessions][disabled]"
    assert_select "button.sync-button[data-resource=attendees]:not([disabled])"
  end

  test "shows counts and recent sync runs" do
    Attendee.create!(external_id: "att_1", name: "Ada Lovelace")
    SyncRun.create!(resource: "attendees", status: "succeeded", started_at: 5.seconds.ago, finished_at: Time.current, records_fetched: 1, records_created: 1)
    SyncRun.create!(resource: "sessions", status: "failed", error_message: "client API returned 500")

    get status_url

    assert_response :success
    assert_includes response.body, "succeeded"
    assert_includes response.body, "failed"
    assert_includes response.body, "client API returned 500"
  end
end
