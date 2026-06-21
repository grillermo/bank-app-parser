# Bank App Parser

Rails 8 app that ingests bank statement screenshots, extracts transactions via OpenAI vision, and visualizes spending on an interactive Inertia React dashboard.

## Commands

```bash
# Test suite
bundle exec rspec

# Dev server (Vite + Rails + Solid Queue in tmux)
./serve-dev

# Database
bin/rails db:migrate
bin/rails db:reset
bin/rails console

# Jobs
bin/rails solid_queue:start
```

This developer's shell exports `RAILS_ENV=production` globally, so any Rails command that touches the database needs an explicit `RAILS_ENV=development` (or `RAILS_ENV=test` for specs) prefix, e.g. `RAILS_ENV=development bin/rails db:migrate`, to avoid hitting the (nonexistent) production DB.

## Architecture Map

### Controllers

| File | Responsibility |
|------|-----------------|
| `app/controllers/application_controller.rb` | Base controller |
| `app/controllers/ingest_controller.rb` | POST /ingest — saves multipart images, enqueues IngestJob |
| `app/controllers/dashboard_controller.rb` | GET / — renders Inertia React dashboard with DashboardStats |
| `app/controllers/health_controller.rb` | GET /health — database + Solid Queue + OpenAI API key presence checks |

### Jobs

| File | Responsibility |
|------|-----------------|
| `app/jobs/application_job.rb` | Base job |
| `app/jobs/ingest_job.rb` | Orchestrates preprocess → stitch → OCR → import; cleans up temp files; notifies Slack on error |

### Services

| File | Responsibility |
|------|-----------------|
| `app/services/image_preprocessor.rb` | Resizes PNGs to <768px (keeping aspect), converts to greyscale via `magick` |
| `app/services/image_stitcher.rb` | Stitches preprocessed images using vendored Python tool via Open3 |
| `app/services/ocr_client.rb` | Sends stitched image to OpenAI vision API; extracts structured transaction JSON |
| `app/services/transaction_importer.rb` | Persists transaction rows to DB with deduplication (via Transaction.dedup_create!) |
| `app/services/dashboard_stats.rb` | Aggregates transactions: top categories/merchants, largest purchases, monthly timeseries |
| `app/services/slack_notifier.rb` | Sends Slack webhook notification on job failure |

## Conventions

- **Ruby** 3.4.7 pinned in `.ruby-version` and `Gemfile`
- **Testing** RSpec (replaces Minitest); 26 specs covering models, jobs, controllers, services
- **Services** Plain Ruby classes with class methods; no inheritance
- **HTTP** `http` gem (not Net::HTTP or HTTPClient)
- **Image Processing** ImageMagick via `magick` command in Open3 subprocess
- **Python** Scripts via `./python_env/bin/python` (vendored environment)
- **Databases** PostgreSQL 18; three DBs (production, test, development) in single Postgres instance
- **Job Queue** Solid Queue (database-backed, no external dependency)
- **Cache** Solid Cache (database-backed)
- **Frontend** Inertia Rails + React + Vite + Tailwind CSS (no authentication, single dashboard)
- **Logging** Rails.logger.debug for step-by-step pipeline progress

## Environment Variables

| Variable | Required | Notes |
|----------|----------|-------|
| `INGEST_TOKEN` | Yes | Bearer token for `/ingest` authorization |
| `OPENAI_API_KEY` | Yes | OpenAI API key (sk-...) |
| `OPENAI_MODEL` | Yes | Model ID (e.g., gpt-5.4-nano-2026-03-17) |
| `SLACK_WEBHOOK_URL` | No | Slack webhook URL for failure notifications; if blank, notifier skips silently |
| `RAILS_PORT` | No | Rails server port (default: 3000) |
| `RAILS_LOG_TO_STDOUT` | No | Set to 1 in solid_queue worker pane for visible logs |

## Key Conventions

### Spend Calculation

**spend = abs(amount) where amount < 0**

Bank transaction amounts are stored as:
- Negative (amount < 0) for expenditures (debits, withdrawals)
- Positive (amount > 0) for income (credits, deposits)

Dashboard and reports always show "spend" by taking `ABS(amount)` where `amount < 0`. This isolates outflow and presents it as positive currency (e.g., -$50.00 purchase displays as $50.00 spend).

### Transaction Deduplication

`Transaction.dedup_create!(batch:, attrs:)` ensures idempotency: same transaction row cannot be inserted twice, even if the pipeline runs multiple times for the same screenshot batch.

### Temp File Cleanup

IngestJob ensures all intermediate files (original uploads, preprocessed PNGs, stitched image) are deleted in the `ensure` block, even on error, to avoid disk bloat.

### Pipeline Logging

Each service logs with a prefix (`[Preprocess]`, `[Stitch]`, `[OCR]`, `[Import]`) for easy debugging and status tracking in logs.
