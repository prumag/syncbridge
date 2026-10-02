require "net/http"
require "json"

module ClientApi
  class Error < StandardError; end

  # Thin HTTP wrapper around the client's REST API.
  class Client
    DEFAULT_PER_PAGE = 100

    def initialize(base_url: ClientApi.config.base_url, token: ClientApi.config.token)
      @base_url = base_url
      @token = token
    end

    # Fetches one page of a collection ("attendees" or "sessions").
    # Returns the parsed body: { "data" => [...], "meta" => { "page" =>, "total_pages" => } }
    def fetch_page(resource, page: 1, per_page: DEFAULT_PER_PAGE)
      uri = URI.join(@base_url, "/api/v1/#{resource}")
      uri.query = URI.encode_www_form(page: page, per_page: per_page)

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "#{resource} page #{page} failed with HTTP #{response.code}"
      end

      JSON.parse(response.body)
    end
  end
end
