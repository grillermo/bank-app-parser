# bank-app-parser — Design

## Purpose
Store and analyze personal bank transactions to optimize finances. Transactions are ingested
as screenshots of bank mobile apps (a series of scroll captures). The app preprocesses, stitches,
OCRs via OpenAI, persists transactions, and renders an analytics dashboard.

## Stack
- Rails 8, Ruby 3.4.7 (rbenv), Postgres 18
- solid_queue (Active Job) + solid_cache (cache store), both in the **primary** DB / unified schema
- RSpec (replaces Minitest)
- Inertia Rails + React + Vite + Tailwind, Chart.js for rendering
- dotenv for config; `http` gem (httprb/http) for all third-party HTTP clients

## Core environment & versioning
- `.ruby-version` = `3.4.7`; Gemfile pins `ruby "3.4.7"`
- App name: `bank_app_parser`
- 3 Postgres databases: `bank_app_parser_development`, `bank_app_parser_test`, `bank_app_parser_production`
- solid_queue + solid_cache tables live in the primary schema (single unified schema, not separate DBs)
- Robust `.gitignore`: `.DS_Store`, `tmp/`, `log/`, `.env`, `config/credentials/*.key`, `config/master.key`, `/python_env`

### Env vars (.env)
- `INGEST_TOKEN` — bearer token for POST /ingest
- `OPENAI_API_KEY`
- `OPENAI_MODEL` = `gpt-5.4-nano-2026-03-17`
- `SLACK_WEBHOOK_URL` — Slack incoming webhook for failure alerts
- `RAILS_PORT`

## Components

### 1. Ingest API
`POST /ingest`
- Auth: `Authorization: Bearer <INGEST_TOKEN>`. Mismatch → `401`.
- Accepts multipart `images[]` (images only; no video).
- Saves uploads to `tmp/ingest/<batch_id>/` with zero-padded ordered filenames (preserve upload order = scroll order).
- Creates `Batch` (status `pending`), enqueues `IngestJob` with `batch_id`.
- Returns `202 Accepted` + `{ batch_id, status }`.

### 2. Data model (single schema)
- `Batch`: `status` (enum: `pending`, `processing`, `completed`, `failed`), `error_message:text`, timestamps.
- `Transaction`: `date:date`, `description:string`, `bank_name:string`, `merchant:string`,
  `cardname:string`, `amount:decimal`, `category:string`, `batch:references`.
  - `amount` negative = debit/expenditure, positive = income/credit.
  - Dedupe within ingestion on (`date`, `description`, `amount`); skip exact duplicates.

### 3. Pipeline — `IngestJob` (solid_queue)
Logs to STDOUT in development; debug log line at each major step.
1. **Preprocess** (ImageMagick, assumed available): for each image, resize so width AND height < 768
   keeping aspect ratio (`-resize 768x768>`), convert to greyscale (`-colorspace Gray`). Write to a
   preprocessed temp dir.
2. **Stitch**: run vendored `python_env/bin/python vendor/image-stitch/stitch.py -i <preprocessed_dir> -o <stitched.png>`
   via `Open3.popen2e`. Overlap-aware stitching collapses repeated scroll regions. Raise on nonzero exit.
3. **OCR** — `OcrClient` (http gem): POST stitched PNG (base64) + the extraction prompt (from spec) to
   OpenAI, model = `OPENAI_MODEL`. Expect a JSON array of objects. Strip any stray markdown fences before parse.
4. **Post-OCR**: parse JSON, build + save `Transaction` records under the batch, dedupe.
5. Set `Batch` → `completed`. Clean up `tmp/ingest/<batch_id>/` and preprocessed temp dir.

**Error handling**: any step failure → rescue sets `Batch` → `failed` with `error_message`, calls
`SlackNotifier.notify(error_details)`, then re-raises (so solid_queue records the failed job). No silent swallow.

### 4. SlackNotifier
- Plain Ruby class using `http` gem.
- `SlackNotifier.notify(text)` → `POST SLACK_WEBHOOK_URL` with header `Content-type: application/json`,
  body `{ "text": text }`. Equivalent to the curl:
  `curl -X POST -H 'Content-type: application/json' --data '{"text":error_details}' <SLACK_WEBHOOK_URL>`
- Webhook URL read from env (secret), never hardcoded.

### 5. Dashboard — `GET /` (no auth)
Inertia + React page, Chart.js. A `DashboardStats` query object computes (all "spend" = `abs(amount)` where `amount < 0`):
1. **Top categories** (3–5) by total spend, with % of overall spend — pie chart.
2. **Top 5 merchants** by total spend — bar chart.
3. **Top 5 largest single purchases** — date, merchant, amount — list.
4. **Spend per category over time** — stacked columns (e.g. by month), colored per category.

### 6. Health — `GET /health`
Dedicated controller. Returns `200` only if all pass, else `503` with failing checks:
- DB connection (`ActiveRecord::Base.connection.active?` / simple query)
- solid_queue reachable (queue tables queryable)
- `OPENAI_API_KEY` present

## Developer experience
- Vite (`vite_rails`) builds assets with HMR; Tailwind JIT regenerates on file change in dev.
- Active Job output to STDOUT in development.
- Debug log lines at each pipeline step for pipeline debugging.
- `./serve-dev` — tmux session: pane 1 rails server (`RAILS_PORT`), pane 2 solid_queue worker (logs to STDOUT).
- `requirements.txt` (opencv-python, numpy) installed into project-local `./python_env` (gitignored).
- `vendor/image-stitch/stitch.py` (+ supporting modules) vendored from nocoo/image-stitch.

## Testing (RSpec)
- Request specs: `/ingest` (401 without token, 202 + enqueues job with valid token), `/health` (200 healthy, 503 when a dependency down).
- `IngestJob` spec: stub `OcrClient`, `Open3.popen2e`, and ImageMagick calls; assert transactions created, batch completed, temp cleaned; failure path sets batch failed + calls SlackNotifier.
- Model specs: `Transaction` validations + dedupe; `Batch` status transitions.
- `DashboardStats` spec: aggregation correctness (categories %, top merchants, largest purchases, timeseries).
- `SlackNotifier` spec: stub http, assert payload shape.

## Documentation
- `README.md`: purpose, architecture, install (Ruby/rbenv, Postgres, ImageMagick, python_env + requirements), how to run (`./serve-dev`), env vars.
- `CLAUDE.md`: added after the app is built.

## Out of scope (YAGNI)
- Video ingestion (images only).
- ActiveStorage (uploads go to temp dir).
- Dashboard auth.
- User accounts / multi-user.
