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

  test "rejects an unknown mode" do
    response, = post_json("/admin/mode", mode: "chaos")
    assert_equal 422, response.status
  end

  test "reset restores the original data and mode" do
    post_json("/admin/mutate", creates: 5)
    post_json("/admin/mode", mode: "flaky")

    _, state = post_json("/admin/reset")

    assert_equal "normal", state["mode"]
    assert_equal MockApi::ATTENDEE_COUNT, state["attendees"]
  end
end
