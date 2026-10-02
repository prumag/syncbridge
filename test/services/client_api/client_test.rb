require "test_helper"

class ClientApi::ClientTest < ActiveSupport::TestCase
  setup do
    @client = ClientApi::Client.new(base_url: "http://client.test", token: "secret")
  end

  test "fetches a page with auth header and pagination params" do
    stub = stub_request(:get, "http://client.test/api/v1/attendees")
      .with(query: { page: "2", per_page: "50" }, headers: { "Authorization" => "Bearer secret" })
      .to_return(status: 200, body: { data: [ { id: "att_1" } ], meta: { page: 2, total_pages: 3 } }.to_json)

    body = @client.fetch_page("attendees", page: 2, per_page: 50)

    assert_requested stub
    assert_equal "att_1", body["data"].first["id"]
    assert_equal 3, body["meta"]["total_pages"]
  end

  test "raises on non-success responses" do
    stub_request(:get, "http://client.test/api/v1/attendees").with(query: hash_including({})).to_return(status: 500)

    error = assert_raises(ClientApi::Error) { @client.fetch_page("attendees") }
    assert_match(/HTTP 500/, error.message)
  end
end
