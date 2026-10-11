require "test_helper"
require_relative "../../mock_api/app"

class MockApiAppTest < ActiveSupport::TestCase
  AUTH = { "HTTP_AUTHORIZATION" => "Bearer test-token" }.freeze

  setup do
    @app = MockApi::App.new
    @request = Rack::MockRequest.new(@app)
  end

  def get_json(path, headers = AUTH)
    response = @request.get(path, headers)
    [ response, JSON.parse(response.body) ]
  end

  def post_json(path, payload = {})
    response = @request.post(path, input: payload.to_json)
    [ response, JSON.parse(response.body) ]
  end

  test "rejects requests without the token" do
    response, = get_json("/api/v1/attendees", {})
    assert_equal 401, response.status
  end

  test "paginates attendees" do
    _, body = get_json("/api/v1/attendees?page=2&per_page=100")

    assert_equal 100, body["data"].size
    assert_equal MockApi::ATTENDEE_COUNT, body["meta"]["total"]
    assert_equal 12, body["meta"]["total_pages"]
    assert_equal "att_101", body["data"].first["id"]
  end

  test "filters by updated_since" do
    post_json("/admin/mutate", updates: 3, creates: 2)
    cutoff = (MockApi::BASE_TIME + MockApi::ATTENDEE_COUNT + MockApi::SESSION_COUNT).iso8601

    _, body = get_json("/api/v1/attendees?updated_since=#{cutoff}&per_page=200")

    assert_operator body["meta"]["total"], :<=, 5
    assert_operator body["meta"]["total"], :>=, 2
  end

  test "rate limited mode returns 429 with Retry-After" do
    post_json("/admin/mode", mode: "rate_limited")

    statuses = (MockApi::RATE_LIMIT + 1).times.map { get_json("/api/v1/sessions").first }

    assert_equal [ 200 ] * MockApi::RATE_LIMIT, statuses.first(MockApi::RATE_LIMIT).map(&:status)
    assert_equal 429, statuses.last.status
    assert_operator statuses.last.headers["retry-after"].to_i, :>=, 1
  end

  test "flaky mode eventually returns server errors" do
    post_json("/admin/mode", mode: "flaky")

    statuses = 40.times.map { get_json("/api/v1/sessions").first.status }

    assert_includes statuses, 500
    assert_includes statuses, 200
  end

  test "serves speakers and sessions that reference them" do
    _, speakers = get_json("/api/v1/speakers?per_page=200")
    _, sessions = get_json("/api/v1/sessions?per_page=200")

    speaker_ids = speakers["data"].map { |s| s["id"] }
    assert_equal MockApi::SPEAKER_COUNT, speakers["meta"]["total"]
    assert_equal %w[company id name title updated_at], speakers["data"].first.keys.sort

    sessions["data"].each do |session|
      assert_operator session["speaker_ids"].size, :>=, 1
      assert_empty session["speaker_ids"] - speaker_ids
    end
  end

  test "mutate can change and create sessions and speakers" do
    _, counts = post_json("/admin/mutate", resource: "speakers", updates: 2, creates: 3)
    assert_equal MockApi::SPEAKER_COUNT + 3, counts["speakers"]

    _, counts = post_json("/admin/mutate", resource: "sessions", updates: 2, creates: 1)
    assert_equal MockApi::SESSION_COUNT + 1, counts["sessions"]

    _, body = get_json("/api/v1/sessions?per_page=200")
    new_session = body["data"].find { |s| s["id"] == "ses_#{MockApi::SESSION_COUNT + 1}" }
    assert_operator new_session["speaker_ids"].size, :>=, 1
  end

  test "mutate rejects an unknown resource" do
    response, = post_json("/admin/mutate", resource: "invoices", updates: 1)
    assert_equal 422, response.status
  end

  test "delete removes records from the API" do
    response, counts = post_json("/admin/delete", attendees: 5, sessions: 2)

    assert_equal 200, response.status
    assert_equal MockApi::ATTENDEE_COUNT - 5, counts["attendees"]
    assert_equal MockApi::SESSION_COUNT - 2, counts["sessions"]
    assert_equal MockApi::SPEAKER_COUNT, counts["speakers"]

    _, body = get_json("/api/v1/attendees?per_page=1")
    assert_equal MockApi::ATTENDEE_COUNT - 5, body["meta"]["total"]
  end

  test "deleting a speaker removes it from sessions and marks those sessions as changed" do
    _, before = get_json("/api/v1/sessions?per_page=200")
    post_json("/admin/delete", speakers: MockApi::SPEAKER_COUNT)
    _, after = get_json("/api/v1/sessions?per_page=200")

    assert_equal 0, get_json("/api/v1/speakers")[1]["meta"]["total"]
    assert(after["data"].all? { |s| s["speaker_ids"].empty? })

    after_by_id = after["data"].index_by { |s| s["id"] }
    before["data"].each do |old|
      assert_operator after_by_id[old["id"]]["updated_at"], :>, old["updated_at"]
    end
  end

  test "new records never reuse the id of a deleted record" do
    post_json("/admin/delete", attendees: 10)
    post_json("/admin/mutate", creates: 10)

    ids = (1..7).flat_map { |page| get_json("/api/v1/attendees?per_page=200&page=#{page}")[1]["data"].map { |a| a["id"] } }

    assert_equal MockApi::ATTENDEE_COUNT, ids.size
    assert_equal ids.uniq.size, ids.size
    assert_includes ids, "att_#{MockApi::ATTENDEE_COUNT + 10}"
  end

  test "delete rejects unknown keys" do
    response, = post_json("/admin/delete", invoices: 1)
    assert_equal 422, response.status
  end

  test "rejects an unknown mode" do
    response, = post_json("/admin/mode", mode: "chaos")
    assert_equal 422, response.status
  end

  test "reset restores the original data and mode" do
    post_json("/admin/mutate", creates: 5)
    post_json("/admin/delete", speakers: 3)
    post_json("/admin/mode", mode: "flaky")

    _, state = post_json("/admin/reset")

    assert_equal "normal", state["mode"]
    assert_equal MockApi::ATTENDEE_COUNT, state["attendees"]
    assert_equal MockApi::SPEAKER_COUNT, state["speakers"]
  end
end
