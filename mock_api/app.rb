require "json"
require "time"
require "rack"

# A stand-in for a client's event-data API. Runs separately from the Rails app.
#
#   GET  /api/v1/attendees?page=1&per_page=100[&updated_since=ISO8601]
#   GET  /api/v1/sessions?page=1&per_page=100[&updated_since=ISO8601]
#   POST /admin/mode     {"mode": "normal|flaky|rate_limited|slow"}
#   POST /admin/mutate   {"updates": 10, "creates": 5}
#   POST /admin/reset
#   GET  /admin/state
#
# Requests to /api/v1 need the header "Authorization: Bearer test-token".
module MockApi
  TOKEN = "test-token".freeze
  BASE_TIME = Time.utc(2026, 9, 1, 8, 0, 0)
  ATTENDEE_COUNT = 1200
  SESSION_COUNT = 60
  MODES = %w[normal flaky rate_limited slow].freeze
  RATE_LIMIT = 5
  RATE_WINDOW_SECONDS = 10
  FLAKY_FAILURE_RATE = 0.3
  SLOW_DELAY_SECONDS = 2

  COMPANIES = %w[Acme Globex Initech Umbrella Hooli Stark Wayne Wonka Vandelay Soylent].freeze
  FIRST_NAMES = %w[Asha Ben Carla Dev Elena Farid Grace Hiro Isla Jorge Kavya Liam Maya Noor Omar Priya].freeze
  LAST_NAMES = %w[Anders Brooks Chen Diaz Evans Fox Gupta Haas Ito Jones Khan Lopez Mehta Nair Ortiz Patel].freeze
  ROOMS = [ "Hall A", "Hall B", "Room 101", "Room 102", "Ballroom", "Studio" ].freeze

  class Store
    attr_reader :mode

    def initialize
      @lock = Mutex.new
      reset!
    end

    def reset!
      @lock.synchronize do
        @rng = Random.new(42)
        @mode = "normal"
        @request_times = []
        @clock = BASE_TIME + ATTENDEE_COUNT + SESSION_COUNT
        @attendees = (1..ATTENDEE_COUNT).map { |i| build_attendee(i, BASE_TIME + i) }
        @sessions = (1..SESSION_COUNT).map { |i| build_session(i, BASE_TIME + ATTENDEE_COUNT + i) }
      end
    end

    def mode=(value)
      @lock.synchronize { @mode = value }
    end

    def collection(resource)
      @lock.synchronize { resource == "attendees" ? @attendees.dup : @sessions.dup }
    end

    # Registers a request for rate limiting. Returns seconds to wait if over the limit, else nil.
    def throttle
      @lock.synchronize do
        now = Time.now.to_f
        @request_times.reject! { |t| now - t > RATE_WINDOW_SECONDS }
        if @request_times.size >= RATE_LIMIT
          (RATE_WINDOW_SECONDS - (now - @request_times.first)).ceil.clamp(1, RATE_WINDOW_SECONDS)
        else
          @request_times << now
          nil
        end
      end
    end

    def flaky_failure?
      @lock.synchronize { @rng.rand < FLAKY_FAILURE_RATE }
    end

    def mutate(updates:, creates:)
      @lock.synchronize do
        updates.times do
          record = @attendees[@rng.rand(@attendees.size)]
          record["company"] = COMPANIES[@rng.rand(COMPANIES.size)]
          record["updated_at"] = tick.iso8601
        end
        creates.times do
          id = @attendees.size + 1
          @attendees << build_attendee(id, tick)
        end
        { attendees: @attendees.size, sessions: @sessions.size }
      end
    end

    def state
      @lock.synchronize { { mode: @mode, attendees: @attendees.size, sessions: @sessions.size } }
    end

    private

    def tick
      @clock += 1
    end

    def build_attendee(id, updated_at)
      first = FIRST_NAMES[@rng.rand(FIRST_NAMES.size)]
      last = LAST_NAMES[@rng.rand(LAST_NAMES.size)]
      {
        "id" => "att_#{id}",
        "name" => "#{first} #{last}",
        "email" => "#{first}.#{last}.#{id}@example.com".downcase,
        "company" => COMPANIES[@rng.rand(COMPANIES.size)],
        "updated_at" => updated_at.iso8601
      }
    end

    def build_session(id, updated_at)
      start = BASE_TIME + (id * 3600)
      {
        "id" => "ses_#{id}",
        "title" => "Session #{id}: #{%w[Keynote Workshop Panel Talk Demo].sample(random: @rng)}",
        "room" => ROOMS[@rng.rand(ROOMS.size)],
        "starts_at" => start.iso8601,
        "ends_at" => (start + 3000).iso8601,
        "updated_at" => updated_at.iso8601
      }
    end
  end

  class App
    def initialize(store = Store.new)
      @store = store
    end

    def call(env)
      request = Rack::Request.new(env)

      case [ request.request_method, request.path_info ]
      in [ "GET", %r{\A/api/v1/(attendees|sessions)\z} ]
        handle_collection(request, Regexp.last_match(1))
      in [ "POST", "/admin/mode" ]
        set_mode(request)
      in [ "POST", "/admin/mutate" ]
        mutate(request)
      in [ "POST", "/admin/reset" ]
        @store.reset!
        json(200, @store.state)
      in [ "GET", "/admin/state" ]
        json(200, @store.state)
      else
        json(404, error: "not found")
      end
    end

    private

    def handle_collection(request, resource)
      return json(401, error: "unauthorized") unless request.get_header("HTTP_AUTHORIZATION") == "Bearer #{TOKEN}"

      case @store.mode
      when "rate_limited"
        wait = @store.throttle
        return json(429, { error: "rate limit exceeded" }, "Retry-After" => wait.to_s) if wait
      when "flaky"
        return json(500, error: "internal error") if @store.flaky_failure?
      when "slow"
        sleep SLOW_DELAY_SECONDS
      end

      records = @store.collection(resource)
      if (since = request.params["updated_since"])
        cutoff = Time.parse(since)
        records = records.select { |r| Time.parse(r["updated_at"]) > cutoff }
      end
      records = records.sort_by { |r| [ r["updated_at"], r["id"] ] }

      per_page = request.params.fetch("per_page", 100).to_i.clamp(1, 200)
      page = [ request.params.fetch("page", 1).to_i, 1 ].max
      total_pages = [ (records.size / per_page.to_f).ceil, 1 ].max
      slice = records.slice((page - 1) * per_page, per_page) || []

      json(200, data: slice, meta: { page: page, per_page: per_page, total: records.size, total_pages: total_pages })
    rescue ArgumentError
      json(400, error: "invalid parameter")
    end

    def set_mode(request)
      mode = parse_body(request)["mode"]
      return json(422, error: "mode must be one of #{MODES.join(', ')}") unless MODES.include?(mode)

      @store.mode = mode
      json(200, @store.state)
    end

    def mutate(request)
      body = parse_body(request)
      counts = @store.mutate(updates: body.fetch("updates", 0).to_i, creates: body.fetch("creates", 0).to_i)
      json(200, counts)
    end

    def parse_body(request)
      raw = request.body.read.to_s
      raw.empty? ? {} : JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def json(status, payload, headers = {})
      [ status, { "content-type" => "application/json" }.merge(headers.transform_keys(&:downcase)), [ JSON.generate(payload) ] ]
    end
  end
end
