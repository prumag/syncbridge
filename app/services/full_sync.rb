# Pulls every record of one resource from the client API and upserts it locally.
# Each run downloads the complete collection.
class FullSync
  MAPPERS = {
    "attendees" => {
      model: Attendee,
      attributes: ->(r) {
        {
          name: r["name"],
          email: r["email"],
          company: r["company"],
          external_updated_at: r["updated_at"]
        }
      }
    },
    "sessions" => {
      model: EventSession,
      attributes: ->(r) {
        {
          title: r["title"],
          room: r["room"],
          starts_at: r["starts_at"],
          ends_at: r["ends_at"],
          external_updated_at: r["updated_at"]
        }
      }
    }
  }.freeze

  def initialize(resource, client: ClientApi::Client.new)
    raise ArgumentError, "unknown resource: #{resource}" unless MAPPERS.key?(resource)

    @resource = resource
    @client = client
    @mapper = MAPPERS.fetch(resource)
  end

  def call
    run = SyncRun.create!(resource: @resource, status: "running", started_at: Time.current)

    begin
      page = 1
      loop do
        body = @client.fetch_page(@resource, page: page)
        body.fetch("data").each { |record| upsert(record, run) }

        break if page >= body.fetch("meta").fetch("total_pages")
        page += 1
      end

      run.finish!(status: "succeeded")
    rescue => e
      run.finish!(status: "failed", error_message: "#{e.class}: #{e.message}")
      raise
    end

    run
  end

  private

  def upsert(record, run)
    model = @mapper[:model]
    row = model.find_or_initialize_by(external_id: record.fetch("id").to_s)
    was_new = row.new_record?

    row.assign_attributes(@mapper[:attributes].call(record))
    row.save!

    run.records_fetched += 1
    if was_new
      run.records_created += 1
    elsif row.saved_changes.except("updated_at").any?
      run.records_updated += 1
    end
    run.save!
  end
end
