require "test_helper"

class FullSyncTest < ActiveSupport::TestCase
  test "creates records across all pages and records the run" do
    client = FakeClient.new([ [ attendee_record(1), attendee_record(2) ], [ attendee_record(3) ] ])

    run = FullSync.new("attendees", client: client).call

    assert_equal 3, Attendee.count
    assert_equal "succeeded", run.status
    assert_equal 3, run.records_fetched
    assert_equal 3, run.records_created
    assert_equal 0, run.records_updated
    assert_not_nil run.finished_at
    assert_equal [ [ "attendees", 1 ], [ "attendees", 2 ] ], client.calls
  end

  test "running twice does not create duplicates and counts only real changes" do
    pages = [ [ attendee_record(1), attendee_record(2) ] ]
    FullSync.new("attendees", client: FakeClient.new(pages)).call

    changed = [ [ attendee_record(1), attendee_record(2, company: "Globex") ] ]
    run = FullSync.new("attendees", client: FakeClient.new(changed)).call

    assert_equal 2, Attendee.count
    assert_equal 2, run.records_fetched
    assert_equal 0, run.records_created
    assert_equal 1, run.records_updated
    assert_equal "Globex", Attendee.find_by!(external_id: "att_2").company
  end

  test "syncs sessions into event sessions" do
    record = {
      "id" => "ses_1", "title" => "Keynote", "room" => "Hall A",
      "starts_at" => "2026-09-02T09:00:00Z", "ends_at" => "2026-09-02T09:50:00Z",
      "updated_at" => "2026-09-01T08:00:00Z"
    }

    FullSync.new("sessions", client: FakeClient.new([ [ record ] ])).call

    session = EventSession.find_by!(external_id: "ses_1")
    assert_equal "Keynote", session.title
    assert_equal "Hall A", session.room
  end

  test "syncs speakers" do
    FullSync.new("speakers", client: FakeClient.new([ [ speaker_record(1, title: "CTO") ] ])).call

    speaker = Speaker.find_by!(external_id: "spk_1")
    assert_equal "CTO", speaker.job_title
    assert_equal "Acme", speaker.company
  end

  test "links sessions to their speakers" do
    FullSync.new("speakers", client: FakeClient.new([ [ speaker_record(1), speaker_record(2), speaker_record(3) ] ])).call

    FullSync.new("sessions", client: FakeClient.new([ [ session_record(1, speaker_ids: %w[spk_1 spk_3]) ] ])).call

    session = EventSession.find_by!(external_id: "ses_1")
    assert_equal %w[spk_1 spk_3], session.speakers.order(:external_id).pluck(:external_id)
  end

  test "changing the speakers of a session counts as an update and replaces the links" do
    FullSync.new("speakers", client: FakeClient.new([ [ speaker_record(1), speaker_record(2) ] ])).call
    FullSync.new("sessions", client: FakeClient.new([ [ session_record(1, speaker_ids: %w[spk_1]) ] ])).call

    run = FullSync.new("sessions", client: FakeClient.new([ [ session_record(1, speaker_ids: %w[spk_2]) ] ])).call

    assert_equal 1, run.records_updated
    assert_equal %w[spk_2], EventSession.find_by!(external_id: "ses_1").speakers.pluck(:external_id)
    assert_equal 1, SessionSpeaker.count
  end

  test "re-syncing unchanged sessions reports no updates" do
    FullSync.new("speakers", client: FakeClient.new([ [ speaker_record(1) ] ])).call
    pages = [ [ session_record(1, speaker_ids: %w[spk_1]) ] ]
    FullSync.new("sessions", client: FakeClient.new(pages)).call

    run = FullSync.new("sessions", client: FakeClient.new(pages)).call

    assert_equal 0, run.records_updated
    assert_equal 1, SessionSpeaker.count
  end

  test "marks the run failed and re-raises when the client errors" do
    client = Object.new
    def client.fetch_page(*, **) = raise(ClientApi::Error, "boom")

    assert_raises(ClientApi::Error) { FullSync.new("attendees", client: client).call }

    run = SyncRun.last
    assert_equal "failed", run.status
    assert_match(/boom/, run.error_message)
  end

  test "rejects unknown resources" do
    assert_raises(ArgumentError) { FullSync.new("invoices") }
  end
end
