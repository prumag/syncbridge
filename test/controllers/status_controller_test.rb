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

  test "offers a sync button for speakers and shows how many are stored" do
    Speaker.create!(external_id: "spk_1", name: "Ada")

    get root_url

    assert_select "button.sync-button[data-resource=speakers]"
    assert_select ".label", text: "Speakers stored"
  end

  test "links each sync run to its detail page" do
    run = SyncRun.create!(resource: "attendees", status: "succeeded", started_at: Time.current)

    get root_url

    assert_select "a[href=?]", run_path(run), text: run.id.to_s
  end

  test "detail page shows one sync run" do
    run = SyncRun.create!(
      resource: "sessions", status: "failed", started_at: 3.seconds.ago, finished_at: Time.current,
      records_fetched: 40, records_created: 10, records_updated: 5,
      error_message: "ClientApi::Error: sessions page 2 failed with HTTP 500"
    )

    get run_url(run)

    assert_response :success
    assert_select "h1", text: "Sync ##{run.id}: sessions"
    assert_select ".badge.failed"
    assert_select ".error-box", text: /HTTP 500/
    assert_select ".label", text: "Unchanged"
    assert_includes response.body, ">25<"
  end

  test "detail page for a running sync refreshes itself" do
    run = SyncRun.create!(resource: "attendees", status: "running", started_at: Time.current)

    get run_url(run)

    assert_response :success
    assert_select "meta[http-equiv=refresh]"
  end

  test "detail page for a missing sync run is a 404" do
    get run_url(id: 999_999)

    assert_response :not_found
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
