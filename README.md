# Syncbridge

A Rails API app that pulls event data (attendees and sessions) from a client's REST API into a local database. It is a small version of the kind of integration backend used to feed a mobile event app.

## Components

| Part | Location | Purpose |
| --- | --- | --- |
| API client | `app/services/client_api/` | HTTP wrapper around the client's API (auth, pagination, error on non-2xx) |
| Full sync | `app/services/full_sync.rb` | Fetches every page of a resource and upserts records by `external_id` |
| Job | `app/jobs/full_sync_job.rb` | Runs a sync in the background (Solid Queue) |
| Sync history | `SyncRun` model, `GET /sync_runs` | One row per sync with status and record counts |
| Endpoints | `app/controllers/` | `POST /sync_runs`, `GET /sync_runs`, `GET /attendees` |
| Mock client API | `mock_api/` | Standalone Rack app that imitates the client's system |

## Setup

Requires Ruby 3.4 (see `.ruby-version`).

```bash
bundle install
bin/rails db:setup
```

## Running

Start the mock client API in one terminal:

```bash
bin/mock_api            # http://localhost:4567
```

Run a sync in another:

```bash
bin/rails 'sync:full[attendees]'     # or 'sync:full[sessions]', or 'sync:full' for both
```

Or through the app:

```bash
bin/rails server
curl -X POST localhost:3000/sync_runs -d resource=attendees
curl localhost:3000/sync_runs
```

Background jobs are processed by Solid Queue (`bin/jobs`).

Configuration (environment variables): `CLIENT_API_URL` (default `http://localhost:4567`), `CLIENT_API_TOKEN` (default `test-token`).

## Mock client API

Seeded with 1200 attendees and 60 sessions. Each record carries an `updated_at` timestamp. List endpoints accept `page`, `per_page` (max 200) and `updated_since` (ISO 8601).

Admin endpoints for testing:

```bash
curl -XPOST localhost:4567/admin/mode   -d '{"mode":"rate_limited"}'   # normal | flaky | rate_limited | slow
curl -XPOST localhost:4567/admin/mutate -d '{"updates":10,"creates":5}' # change/add attendees
curl -XPOST localhost:4567/admin/reset                                  # restore seed data
curl localhost:4567/admin/state
```

Modes:

- `rate_limited`: 5 requests per 10 seconds, then `429` with a `Retry-After` header
- `flaky`: about 30% of requests return `500`
- `slow`: every request takes 2 seconds

## Tests

```bash
bin/rails test
bin/rubocop
```
