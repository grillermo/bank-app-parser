# Bank App Parser

A Rails 8 application that ingests bank statement screenshots, automatically extracts transactions via OCR, and visualizes spending patterns on an interactive dashboard.

## Purpose

Upload bank statement screenshots → automatically preprocess, stitch, and OCR them → create transaction records → explore spending via an Inertia React dashboard with 4 visualizations (top categories, merchants, purchases, and monthly trends).

## Architecture

1. **Ingest Endpoint** (`/ingest`) — Token-authenticated multipart upload handler
2. **IngestJob** — Background job orchestrating the pipeline
3. **ImagePreprocessor** — Resizes to <768px, converts to greyscale
4. **ImageStitcher** — Stitches multiple screenshots using Python vendored tool
5. **OcrClient** — Extracts transaction rows via OpenAI vision API
6. **TransactionImporter** — Persists transactions with deduplication
7. **DashboardController** — Serves React frontend with DashboardStats
8. **DashboardStats** — 4 visualizations (top categories, merchants, largest purchases, monthly timeseries)

## Prerequisites

- **Ruby** 3.4.7 (via rbenv)
- **PostgreSQL** 18
- **ImageMagick** (`magick` command)
- **Python 3** (for `./python_env`)
- **Node.js** (for Vite/npm)
- **tmux** (for `./serve-dev`)

## Setup

```bash
# Set up Ruby
rbenv local 3.4.7

# Install gem dependencies
bundle install

# Set up Python environment
python3 -m venv python_env
./python_env/bin/pip install -r requirements.txt

# Install Node dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env and fill in:
#   OPENAI_API_KEY=sk-...
#   INGEST_TOKEN=your-secret-token
#   SLACK_WEBHOOK_URL=https://hooks.slack.com/...
#   RAILS_PORT=3000

# Create and migrate databases
# Note: if your shell exports RAILS_ENV=production globally, prefix DB-touching
# commands with RAILS_ENV=development (or RAILS_ENV=test for specs) to avoid
# hitting the (nonexistent) production database, e.g.:
RAILS_ENV=development bin/rails db:create db:migrate

# Launch dev server (Vite, Rails, Solid Queue in tmux)
./serve-dev
```

## Environment Variables

| Variable            | Required | Example / Notes                                                        |
|---------------------|----------|------------------------------------------------------------------------|
| `INGEST_TOKEN`      | Yes      | Secret bearer token for `/ingest` endpoint (e.g., `dev-local-token`)   |
| `OPENAI_API_KEY`    | Yes      | OpenAI API key (sk-...)                                                |
| `OPENAI_MODEL`      | Yes      | Model ID (e.g., `gpt-5.4-nano-2026-03-17`)                             |
| `SLACK_WEBHOOK_URL` | No       | Slack webhook for job failure notifications                            |
| `RAILS_PORT`        | No       | Rails server port (default: 3000)                                      |

## Example Usage

```bash
# Export token and endpoint
INGEST_TOKEN="dev-local-token"
ENDPOINT="http://localhost:3000/ingest"

# Upload screenshots
curl -X POST \
  -H "Authorization: Bearer $INGEST_TOKEN" \
  -F "images[]=@statement-page-1.png" \
  -F "images[]=@statement-page-2.png" \
  "$ENDPOINT"

# Response
{
  "batch_id": 1,
  "status": "pending"
}

# View dashboard
# http://localhost:3000
```

## Development Commands

```bash
# Run test suite
bundle exec rspec

# Launch dev server (Vite + Rails + Solid Queue)
./serve-dev

# Migrate database
bin/rails db:migrate

# Rails console
bin/rails console
```

## Architecture Overview

```
POST /ingest
  ↓
IngestController (token auth)
  ↓ enqueue
IngestJob
  ├ ImagePreprocessor.process
  ├ ImageStitcher.stitch
  ├ OcrClient.extract
  └ TransactionImporter.import
    ↓
GET /
  ↓
DashboardController
  ↓
DashboardStats.to_h
  ├ top_categories (5)
  ├ top_merchants (5)
  ├ largest_purchases (5)
  └ category_timeseries (monthly)
```
