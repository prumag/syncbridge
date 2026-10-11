require "json"
require "time"
require "rack"

# A stand-in for a client's event-data API. Runs separately from the Rails app.
#
#   GET  /api/v1/attendees?page=1&per_page=100[&updated_since=ISO8601]
#   GET  /api/v1/sessions?page=1&per_page=100[&updated_since=ISO8601]
#   GET  /api/v1/speakers?page=1&per_page=100[&updated_since=ISO8601]
#   POST /admin/mode     {"mode": "normal|flaky|rate_limited|slow"}
#   POST /admin/mutate   {"resource": "attendees", "updates": 10, "creates": 5}
#   POST /admin/delete   {"attendees": 5, "sessions": 2, "speakers": 1}
#   POST /admin/reset
#   GET  /admin/state
#
# Requests to /api/v1 need the header "Authorization: Bearer test-token".
#
# Sessions list the ids of their speakers in "speaker_ids". Deleted records simply
# stop appearing in the API; the client never reports a deletion in any other way.
module MockApi
  TOKEN = "test-token".freeze
  BASE_TIME = Time.utc(2026, 9, 1, 8, 0, 0)
  ATTENDEE_COUNT = 1200
  SESSION_COUNT = 60
  SPEAKER_COUNT = 25
  RESOURCES = %w[attendees sessions speakers].freeze
  MODES = %w[normal flaky rate_limited slow].freeze
  RATE_LIMIT = 5
  RATE_WINDOW_SECONDS = 10
  FLAKY_FAILURE_RATE = 0.3
  SLOW_DELAY_SECONDS = 2

  COMPANIES = %w[Acme Globex Initech Umbrella Hooli Stark Wayne Wonka Vandelay Soylent].freeze
  FIRST_NAMES = %w[Asha Ben Carla Dev Elena Farid Grace Hiro Isla Jorge Kavya Liam Maya Noor Omar Priya].freeze
  LAST_NAMES = %w[Anders Brooks Chen Diaz Evans Fox Gupta Haas Ito Jones Khan Lopez Mehta Nair Ortiz Patel].freeze
  ROOMS = [ "Hall A", "Hall B", "Room 101", "Room 102", "Ballroom", "Studio" ].freeze
  JOB_TITLES = [ "Engineer", "Designer", "Product Manager", "Researcher", "CTO", "Founder", "Analyst" ].freeze

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
        @clock = BASE_TIME + ATTENDEE_COUNT + SESSION_COUNT + SPEAKER_COUNT
        @next_id = {
          "attendees" => ATTENDEE_COUNT + 1,
          "sessions" => SESSION_COUNT + 1,
          "speakers" => SPEAKER_COUNT + 1
        }
        speaker_pool = (1..SPEAKER_COUNT).map { |i| "spk_#{i}" }
        @records = {
          "attendees" => (1..ATTENDEE_COUNT).map { |i| build_attendee(i, BASE_TIME + i) },
          "sessions" => (1..SESSION_COUNT).map do |i|
            build_session(i, BASE_TIME + ATTENDEE_COUNT + i, pick_speaker_ids(speaker_pool))
          end,
          "speakers" => (1..SPEAKER_COUNT).map { |i| build_speaker(i, BASE_TIME + ATTENDEE_COUNT + SESSION_COUNT + i) }
        }
      end
    end

    def mode=(value)
      @lock.synchronize { @mode = value }
    end

    def collection(resource)
      @lock.synchronize { @records.fetch(resource).map(&:dup) }
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

    # Changes `updates` random records and adds `creates` new ones, each stamped with a fresh updated_at.
    def mutate(resource:, updates:, creates:)
      @lock.synchronize do
        records = @records.fetch(resource)

        updates.times do
          break if records.empty?

          record = records[@rng.rand(records.size)]
          case resource
          when "sessions" then record["room"] = ROOMS[@rng.rand(ROOMS.size)]
          else record["company"] = COMPANIES[@rng.rand(COMPANIES.size)]
          end
          record["updated_at"] = tick.iso8601
        end

        creates.times do
          id = @next_id[resource]
          @next_id[resource] += 1
          records << build_new(resource, id, tick)
        end

        counts
      end
    end

    # Removes random records. Removing a speaker also drops it from the sessions that listed it,
    # which counts as a change to those sessions.
    def remove(amounts)
      @lock.synchronize do
        amounts.each do |resource, amount|
          records = @records.fetch(resource)
          amount.clamp(0, records.size).times do
            removed = records.delete_at(@rng.rand(records.size))
            detach_speaker(removed["id"]) if resource == "speakers"
          end
        end

        counts
      end
    end

    def state
      @lock.synchronize { { mode: @mode }.merge(counts) }
    end

    private

    def counts
      RESOURCES.to_h { |resource| [ resource.to_sym, @records.fetch(resource).size ] }
    end

    def tick
      @clock += 1
    end

    def detach_speaker(speaker_id)
      @records["sessions"].each do |session|
        next unless session["speaker_ids"].include?(speaker_id)

        session["speaker_ids"] = session["speaker_ids"] - [ speaker_id ]
        session["updated_at"] = tick.iso8601
      end
    end

    def pick_speaker_ids(pool)
      pool.sample(1 + @rng.rand(2), random: @rng).sort_by { |id| id.delete_prefix("spk_").to_i }
    end

    def build_new(resource, id, updated_at)
      case resource
      when "attendees" then build_attendee(id, updated_at)
      when "sessions" then build_session(id, updated_at, pick_speaker_ids(@records["speakers"].map { |s| s["id"] }))
      when "speakers" then build_speaker(id, updated_at)
      end
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

    def build_session(id, updated_at, speaker_ids)
      start = BASE_TIME + (id * 3600)
      {
        "id" => "ses_#{id}",
        "title" => "Session #{id}: #{%w[Keynote Workshop Panel Talk Demo].sample(random: @rng)}",
        "room" => ROOMS[@rng.rand(ROOMS.size)],
        "starts_at" => start.iso8601,
        "ends_at" => (start + 3000).iso8601,
        "speaker_ids" => speaker_ids,
        "updated_at" => updated_at.iso8601
      }
    end

    def build_speaker(id, updated_at)
      first = FIRST_NAMES[@rng.rand(FIRST_NAMES.size)]
      last = LAST_NAMES[@rng.rand(LAST_NAMES.size)]
      {
        "id" => "spk_#{id}",
        "name" => "#{first} #{last}",
        "company" => COMPANIES[@rng.rand(COMPANIES.size)],
        "title" => JOB_TITLES[@rng.rand(JOB_TITLES.size)],
        "updated_at" => updated_at.iso8601
      }
    end
  end

  class App
    COLLECTION_PATH = %r{\A/api/v1/(#{RESOURCES.join('|')})\z}

    def initialize(store = Store.new)
      @store = store
    end

    def call(env)
      request = Rack::Request.new(env)

      case [ request.request_method, request.path_info ]
      in [ "GET", COLLECTION_PATH ]
        handle_collection(request, Regexp.last_match(1))
      in [ "POST", "/admin/mode" ]
        set_mode(request)
      in [ "POST", "/admin/mutate" ]
        mutate(request)
      in [ "POST", "/admin/delete" ]
        remove(request)
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
      resource = body.fetch("resource", "attendees")
      return json(422, error: "resource must be one of #{RESOURCES.join(', ')}") unless RESOURCES.include?(resource)

      counts = @store.mutate(resource: resource, updates: body.fetch("updates", 0).to_i, creates: body.fetch("creates", 0).to_i)
      json(200, counts)
    end

    def remove(request)
      body = parse_body(request)
      return json(422, error: "keys must be among #{RESOURCES.join(', ')}") unless (body.keys - RESOURCES).empty?

      json(200, @store.remove(body.transform_values(&:to_i)))
    end

    def parse_body(request)
      raw = request.body.read.to_s
      parsed = raw.empty? ? {} : JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def json(status, payload, headers = {})
      [ status, { "content-type" => "application/json" }.merge(headers.transform_keys(&:downcase)), [ JSON.generate(payload) ] ]
    end
  end
end
