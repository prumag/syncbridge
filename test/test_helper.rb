ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    # Stands in for ClientApi::Client with canned pages of records.
    class FakeClient
      attr_reader :calls

      def initialize(pages)
        @pages = pages
        @calls = []
      end

      def fetch_page(resource, page: 1, per_page: nil)
        @calls << [ resource, page ]
        { "data" => @pages.fetch(page - 1), "meta" => { "page" => page, "total_pages" => @pages.size } }
      end
    end

    def attendee_record(id, name: "Person #{id}", company: "Acme", updated_at: "2026-09-01T08:00:00Z")
      { "id" => "att_#{id}", "name" => name, "email" => "p#{id}@example.com", "company" => company, "updated_at" => updated_at }
    end
  end
end
