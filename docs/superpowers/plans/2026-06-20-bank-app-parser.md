# bank-app-parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Rails app that ingests bank-app screenshots, preprocesses + stitches + OCRs them via OpenAI into transactions, and renders an analytics dashboard.

**Architecture:** `POST /ingest` (bearer auth) saves uploaded images to a temp dir and enqueues a solid_queue `IngestJob`. The job preprocesses (ImageMagick greyscale + resize), stitches (vendored Python `stitch.py` via Open3), OCRs (OpenAI vision via `http` gem), and persists `Transaction`s under a `Batch`. Failures alert Slack. The root page is an Inertia+React dashboard (Chart.js) reading aggregates from a `DashboardStats` query object.

**Tech Stack:** Rails 8, Ruby 3.4.7, Postgres 18, solid_queue + solid_cache (primary DB), RSpec, Inertia Rails + React + Vite + Tailwind, Chart.js, dotenv, `http` gem, Python (opencv-python, numpy) for stitching.

## Global Constraints

- Ruby version: `3.4.7` (rbenv). `.ruby-version` = `3.4.7`; Gemfile pins `ruby "3.4.7"`.
- App name: `bank_app_parser`. Databases: `bank_app_parser_development`, `bank_app_parser_test`, `bank_app_parser_production`.
- Single unified schema: solid_queue + solid_cache tables live in the primary DB (not separate databases).
- Cache store = solid_cache; Active Job adapter = solid_queue.
- Use the `http` gem (httprb/http) for ALL third-party HTTP calls.
- All views via Inertia Rails + React; all styling via Tailwind; charts via Chart.js; assets built by Vite with HMR in dev.
- Active Job logs to STDOUT in development.
- Debug log line at every major pipeline step.
- Env vars (`.env`, dotenv): `INGEST_TOKEN`, `OPENAI_API_KEY`, `OPENAI_MODEL` (= `gpt-5.4-nano-2026-03-17`), `SLACK_WEBHOOK_URL`, `RAILS_PORT`.
- `amount` decimal: negative = debit/expenditure, positive = income/credit. "Spend" = `abs(amount)` where `amount < 0`.
- `.gitignore` ignores `.DS_Store`, `tmp/`, `log/`, `.env`, `config/credentials/*.key`, `config/master.key`, `/python_env`.

---

## File Structure

- `app/controllers/ingest_controller.rb` — POST /ingest, bearer auth, temp-dir save, enqueue.
- `app/controllers/dashboard_controller.rb` — GET / Inertia render.
- `app/controllers/health_controller.rb` — GET /health dependency checks.
- `app/models/batch.rb`, `app/models/transaction.rb`.
- `app/jobs/ingest_job.rb` — pipeline orchestrator.
- `app/services/image_preprocessor.rb` — ImageMagick resize+greyscale.
- `app/services/image_stitcher.rb` — Open3 call to stitch.py.
- `app/services/ocr_client.rb` — OpenAI vision call.
- `app/services/transaction_importer.rb` — JSON → Transaction records + dedupe.
- `app/services/dashboard_stats.rb` — aggregation query object.
- `app/services/slack_notifier.rb` — failure alerts.
- `app/frontend/` — Inertia React entry + `pages/Dashboard.jsx` + chart components.
- `vendor/image-stitch/stitch.py` (+ modules) — vendored stitch tool.
- `requirements.txt`, `serve-dev`, `README.md`, `CLAUDE.md`.

---

### Task 1: Rails app scaffold + Ruby + Postgres + RSpec + dotenv

**Files:**
- Create: whole Rails skeleton, `.ruby-version`, `Gemfile`, `.gitignore`, `.env`, `.env.example`, `config/database.yml`, `spec/spec_helper.rb`, `spec/rails_helper.rb`.

**Interfaces:**
- Produces: a booting Rails 8 app named `bank_app_parser`, `bundle exec rspec` green, three Postgres DBs.

- [ ] **Step 1: Generate the app**

The repo already contains `docs/`. Generate into the current directory.

```bash
cd /Users/grillermo/c/bank-app-parser
rbenv local 3.4.7
gem install rails
rails new . --name=bank_app_parser --database=postgresql --skip-test --skip-jbuilder --force --skip-git
```

- [ ] **Step 2: Pin Ruby in Gemfile**

Ensure the top of `Gemfile` reads exactly:

```ruby
source "https://rubygems.org"
ruby "3.4.7"
```

- [ ] **Step 3: Add gems**

Add to `Gemfile`:

```ruby
gem "dotenv-rails", groups: [:development, :test]
gem "http"
gem "inertia_rails"
gem "vite_rails"

group :development, :test do
  gem "rspec-rails"
end
```

Run:

```bash
bundle install
```

- [ ] **Step 4: Configure database.yml**

Replace `config/database.yml` with (single primary DB per env; solid_* share it):

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  <<: *default
  database: bank_app_parser_development

test:
  <<: *default
  database: bank_app_parser_test

production:
  <<: *default
  database: bank_app_parser_production
  username: bank_app_parser
  password: <%= ENV["BANK_APP_PARSER_DATABASE_PASSWORD"] %>
```

- [ ] **Step 5: Create env files**

Create `.env`:

```
INGEST_TOKEN=dev-local-token
OPENAI_API_KEY=sk-replace-me
OPENAI_MODEL=gpt-5.4-nano-2026-03-17
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/REPLACE/ME
RAILS_PORT=3000
```

Create `.env.example` with the same keys but blank/placeholder values.

- [ ] **Step 6: Harden .gitignore**

Append to `.gitignore`:

```
.DS_Store
/tmp/*
!/tmp/.keep
/log/*
!/log/.keep
.env
/config/credentials/*.key
/config/master.key
/python_env
/node_modules
```

- [ ] **Step 7: Install RSpec**

```bash
bin/rails generate rspec:install
```

- [ ] **Step 8: Create DBs and verify**

```bash
bin/rails db:create
bundle exec rspec
```

Expected: `db:create` makes development + test DBs; `rspec` reports `0 examples, 0 failures`.

- [ ] **Step 9: Verify boot**

```bash
bin/rails runner 'puts "boot ok: #{Rails.application.class.module_parent_name}"'
```

Expected: `boot ok: BankAppParser`

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold Rails 8 app with Postgres, RSpec, dotenv"
```

---

### Task 2: solid_queue + solid_cache in primary DB, STDOUT job logs

**Files:**
- Modify: `Gemfile`, `config/environments/development.rb`, `config/application.rb`, `config/cache.yml`, `config/queue.yml`.
- Create: solid_queue + solid_cache migrations in primary schema.

**Interfaces:**
- Produces: `Rails.application.config.active_job.queue_adapter == :solid_queue`; solid_queue + solid_cache tables in the primary DB.

- [ ] **Step 1: Add gems**

Add to `Gemfile`, then `bundle install`:

```ruby
gem "solid_queue"
gem "solid_cache"
```

- [ ] **Step 2: Install into primary DB**

Generate migrations into the primary database (no separate `queue`/`cache` databases):

```bash
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
```

If the generators created `config/database.yml` entries for separate `queue`/`cache` databases or `db/queue_schema.rb` / `db/cache_schema.rb`, delete those entries and instead keep the generated migrations under `db/migrate/`. Confirm the migration files exist in `db/migrate/` (solid_queue tables + solid_cache `solid_cache_entries`).

- [ ] **Step 3: Configure adapters**

In `config/application.rb` inside the application class:

```ruby
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :primary } }
config.cache_store = :solid_cache_store
```

- [ ] **Step 4: STDOUT job logging in development**

In `config/environments/development.rb`:

```ruby
config.solid_queue.silence_polling = true
if ENV["RAILS_LOG_TO_STDOUT"].present?
  logger = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = config.log_formatter
  config.logger = ActiveSupport::TaggedLogging.new(logger)
end
```

- [ ] **Step 5: Migrate and verify**

```bash
bin/rails db:migrate
bin/rails runner 'puts ActiveRecord::Base.connection.tables.grep(/solid/).inspect'
```

Expected: includes `solid_queue_jobs`, `solid_queue_ready_executions`, `solid_cache_entries`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: configure solid_queue and solid_cache in primary database"
```

---

### Task 3: Batch and Transaction models

**Files:**
- Create: `db/migrate/*_create_batches.rb`, `db/migrate/*_create_transactions.rb`, `app/models/batch.rb`, `app/models/transaction.rb`.
- Test: `spec/models/batch_spec.rb`, `spec/models/transaction_spec.rb`.

**Interfaces:**
- Produces:
  - `Batch` statuses: `pending`, `processing`, `completed`, `failed`; `#error_message`.
  - `Transaction` attrs: `date:date`, `description:string`, `bank_name`, `merchant`, `cardname`, `amount:decimal`, `category`, `batch:references`.
  - `Transaction.dedup_create!(batch:, attrs:)` → creates unless an existing row in the same import matches (`date`, `description`, `amount`); returns the record or `nil` if skipped.

- [ ] **Step 1: Write failing model specs**

`spec/models/batch_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Batch do
  it "defaults to pending status" do
    expect(Batch.create!.status).to eq("pending")
  end

  it "supports the full status lifecycle" do
    batch = Batch.create!
    batch.processing!
    batch.completed!
    expect(batch.completed?).to be(true)
  end
end
```

`spec/models/transaction_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Transaction do
  let(:batch) { Batch.create! }
  let(:attrs) do
    { date: "2025-10-12", description: "COFFEE", amount: -4.5,
      bank_name: "unknown", merchant: "Starbucks", cardname: "unknown", category: "Food" }
  end

  it "requires date, description, amount" do
    t = Transaction.new(batch: batch)
    expect(t).not_to be_valid
    expect(t.errors.attribute_names).to include(:date, :description, :amount)
  end

  it "creates a transaction via dedup_create!" do
    expect { Transaction.dedup_create!(batch: batch, attrs: attrs) }
      .to change(Transaction, :count).by(1)
  end

  it "skips duplicates within the same batch" do
    Transaction.dedup_create!(batch: batch, attrs: attrs)
    result = Transaction.dedup_create!(batch: batch, attrs: attrs)
    expect(result).to be_nil
    expect(Transaction.count).to eq(1)
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/models -f doc
```

Expected: FAIL (`uninitialized constant Batch` / `Transaction`).

- [ ] **Step 3: Generate migrations**

```bash
bin/rails generate migration CreateBatches
bin/rails generate migration CreateTransactions
```

Fill `db/migrate/*_create_batches.rb`:

```ruby
class CreateBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :batches do |t|
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.timestamps
    end
  end
end
```

Fill `db/migrate/*_create_transactions.rb`:

```ruby
class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :batch, null: false, foreign_key: true
      t.date :date, null: false
      t.string :description, null: false
      t.string :bank_name, default: "unknown"
      t.string :merchant, default: "unknown"
      t.string :cardname, default: "unknown"
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :category, default: "unknown"
      t.timestamps
    end
  end
end
```

- [ ] **Step 4: Write models**

`app/models/batch.rb`:

```ruby
class Batch < ApplicationRecord
  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  has_many :transactions, dependent: :destroy

  def fail!(message)
    update!(status: :failed, error_message: message)
  end
end
```

`app/models/transaction.rb`:

```ruby
class Transaction < ApplicationRecord
  belongs_to :batch
  validates :date, :description, :amount, presence: true

  def self.dedup_create!(batch:, attrs:)
    attrs = attrs.symbolize_keys
    return nil if batch.transactions.exists?(
      date: attrs[:date], description: attrs[:description], amount: attrs[:amount]
    )
    batch.transactions.create!(attrs)
  end
end
```

- [ ] **Step 5: Migrate and run specs**

```bash
bin/rails db:migrate
bundle exec rspec spec/models -f doc
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Batch and Transaction models with dedup"
```

---

### Task 4: SlackNotifier

**Files:**
- Create: `app/services/slack_notifier.rb`.
- Test: `spec/services/slack_notifier_spec.rb`.

**Interfaces:**
- Produces: `SlackNotifier.notify(text)` → POSTs `{ "text": text }` JSON to `ENV["SLACK_WEBHOOK_URL"]` via `http` gem. No-op (logs) if URL blank.

- [ ] **Step 1: Write failing spec**

`spec/services/slack_notifier_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe SlackNotifier do
  it "posts JSON text to the webhook" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SLACK_WEBHOOK_URL").and_return("https://hooks.slack.com/services/x")

    fake = double(post: double(status: double(success?: true)))
    expect(HTTP).to receive(:headers)
      .with("Content-type" => "application/json").and_return(fake)
    expect(fake).to receive(:post)
      .with("https://hooks.slack.com/services/x", json: { text: "boom" })
      .and_return(double(status: double(success?: true)))

    SlackNotifier.notify("boom")
  end

  it "no-ops when webhook url is blank" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SLACK_WEBHOOK_URL").and_return(nil)
    expect(HTTP).not_to receive(:headers)
    SlackNotifier.notify("boom")
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/slack_notifier_spec.rb
```

Expected: FAIL (`uninitialized constant SlackNotifier`).

- [ ] **Step 3: Implement**

`app/services/slack_notifier.rb`:

```ruby
class SlackNotifier
  def self.notify(text)
    url = ENV["SLACK_WEBHOOK_URL"]
    if url.blank?
      Rails.logger.warn("[SlackNotifier] SLACK_WEBHOOK_URL blank; skipping: #{text}")
      return
    end
    HTTP.headers("Content-type" => "application/json").post(url, json: { text: text })
  rescue => e
    Rails.logger.error("[SlackNotifier] failed: #{e.message}")
  end
end
```

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rspec spec/services/slack_notifier_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SlackNotifier for failure alerts"
```

---

### Task 5: Ingest API endpoint

**Files:**
- Create: `app/controllers/ingest_controller.rb`.
- Modify: `config/routes.rb`.
- Test: `spec/requests/ingest_spec.rb`.

**Interfaces:**
- Consumes: `Batch`, `IngestJob` (job defined here as a stub, fully implemented in Task 9).
- Produces:
  - `POST /ingest` requires `Authorization: Bearer <INGEST_TOKEN>` → 401 otherwise.
  - Saves each uploaded file to `Rails.root.join("tmp/ingest/<batch_id>/")` with zero-padded ordered names (`000.png`, `001.png`, …).
  - Enqueues `IngestJob.perform_later(batch.id)`. Returns `202` + `{ batch_id:, status: }`.
  - Temp dir path helper: `IngestController.batch_dir(batch_id)` → `Rails.root.join("tmp/ingest", batch_id.to_s)`.

- [ ] **Step 1: Create a stub job so the controller can enqueue**

`app/jobs/ingest_job.rb`:

```ruby
class IngestJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    # Implemented in Task 9.
  end
end
```

- [ ] **Step 2: Write failing request spec**

`spec/requests/ingest_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "POST /ingest" do
  let(:token) { "dev-local-token" }
  before { allow(ENV).to receive(:[]).and_call_original }
  before { allow(ENV).to receive(:[]).with("INGEST_TOKEN").and_return(token) }

  def image
    Rack::Test::UploadedFile.new(StringIO.new("fakebytes"), "image/png", original_filename: "shot.png")
  end

  it "rejects requests without the bearer token" do
    post "/ingest", params: { images: [image] }
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts images, creates a batch, enqueues the job, saves files" do
    expect {
      post "/ingest", params: { images: [image, image] },
           headers: { "Authorization" => "Bearer #{token}" }
    }.to have_enqueued_job(IngestJob).and change(Batch, :count).by(1)

    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    batch_id = body["batch_id"]
    dir = IngestController.batch_dir(batch_id)
    expect(Dir.glob(dir.join("*.png")).sort).to eq([dir.join("000.png").to_s, dir.join("001.png").to_s])
  ensure
    FileUtils.rm_rf(IngestController.batch_dir(body["batch_id"])) if defined?(body) && body
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
bundle exec rspec spec/requests/ingest_spec.rb
```

Expected: FAIL (no route / controller).

- [ ] **Step 4: Add route**

In `config/routes.rb`:

```ruby
post "/ingest", to: "ingest#create"
```

- [ ] **Step 5: Implement controller**

`app/controllers/ingest_controller.rb`:

```ruby
class IngestController < ActionController::API
  before_action :authenticate

  def self.batch_dir(batch_id)
    Rails.root.join("tmp/ingest", batch_id.to_s)
  end

  def create
    files = Array(params[:images]).reject(&:blank?)
    return render(json: { error: "no images" }, status: :unprocessable_entity) if files.empty?

    batch = Batch.create!
    dir = self.class.batch_dir(batch.id)
    FileUtils.mkdir_p(dir)
    files.each_with_index do |file, i|
      File.binwrite(dir.join(format("%03d.png", i)), file.read)
    end
    Rails.logger.debug("[Ingest] saved #{files.size} images for batch #{batch.id} to #{dir}")
    IngestJob.perform_later(batch.id)

    render json: { batch_id: batch.id, status: batch.status }, status: :accepted
  end

  private

  def authenticate
    header = request.headers["Authorization"].to_s
    token = header.split(" ", 2).last
    unless ActiveSupport::SecurityUtils.secure_compare(token.to_s, ENV["INGEST_TOKEN"].to_s)
      render json: { error: "unauthorized" }, status: :unauthorized
    end
  end
end
```

- [ ] **Step 6: Run to verify pass**

```bash
bundle exec rspec spec/requests/ingest_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add authenticated /ingest endpoint that enqueues IngestJob"
```

---

### Task 6: ImagePreprocessor (ImageMagick)

**Files:**
- Create: `app/services/image_preprocessor.rb`.
- Test: `spec/services/image_preprocessor_spec.rb`.

**Interfaces:**
- Produces: `ImagePreprocessor.process(input_dir:, output_dir:)` → for each `*.png` in `input_dir` (sorted), runs ImageMagick to greyscale + resize so width AND height < 768 keeping aspect, writes same filename into `output_dir`; returns sorted array of output paths. Raises `RuntimeError` on a nonzero magick exit.

- [ ] **Step 1: Write failing spec**

`spec/services/image_preprocessor_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ImagePreprocessor do
  it "runs greyscale + resize for each image and returns outputs" do
    in_dir = Rails.root.join("tmp/spec_in"); out_dir = Rails.root.join("tmp/spec_out")
    FileUtils.mkdir_p(in_dir); FileUtils.mkdir_p(out_dir)
    File.write(in_dir.join("000.png"), "x"); File.write(in_dir.join("001.png"), "x")

    commands = []
    allow(Open3).to receive(:popen2e) do |*cmd, &blk|
      commands << cmd
      blk.call(nil, StringIO.new(""), double(value: double(success?: true)))
    end

    out = ImagePreprocessor.process(input_dir: in_dir, output_dir: out_dir)
    expect(out.size).to eq(2)
    expect(commands.first).to include("-colorspace", "Gray", "-resize", "767x767>")
  ensure
    FileUtils.rm_rf(in_dir); FileUtils.rm_rf(out_dir)
  end

  it "raises when magick fails" do
    in_dir = Rails.root.join("tmp/spec_in2"); out_dir = Rails.root.join("tmp/spec_out2")
    FileUtils.mkdir_p(in_dir); FileUtils.mkdir_p(out_dir)
    File.write(in_dir.join("000.png"), "x")
    allow(Open3).to receive(:popen2e) do |*_cmd, &blk|
      blk.call(nil, StringIO.new("bad"), double(value: double(success?: false)))
    end
    expect { ImagePreprocessor.process(input_dir: in_dir, output_dir: out_dir) }
      .to raise_error(RuntimeError, /preprocess failed/)
  ensure
    FileUtils.rm_rf(in_dir); FileUtils.rm_rf(out_dir)
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/image_preprocessor_spec.rb
```

Expected: FAIL (`uninitialized constant ImagePreprocessor`).

- [ ] **Step 3: Implement**

`app/services/image_preprocessor.rb`:

```ruby
require "open3"

class ImagePreprocessor
  # Resize so width AND height < 768 (use 767 cap) keeping aspect, convert greyscale.
  def self.process(input_dir:, output_dir:)
    inputs = Dir.glob(File.join(input_dir, "*.png")).sort
    inputs.map do |src|
      dest = File.join(output_dir, File.basename(src))
      cmd = ["magick", src, "-colorspace", "Gray", "-resize", "767x767>", dest]
      Rails.logger.debug("[Preprocess] #{cmd.join(' ')}")
      Open3.popen2e(*cmd) do |_in, out, wait|
        output = out.read
        raise "preprocess failed: #{output}" unless wait.value.success?
      end
      dest
    end
  end
end
```

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rspec spec/services/image_preprocessor_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ImagePreprocessor (greyscale + resize via ImageMagick)"
```

---

### Task 7: Vendored stitch tool + ImageStitcher

**Files:**
- Create: `vendor/image-stitch/stitch.py` (+ any modules), `requirements.txt`, `app/services/image_stitcher.rb`.
- Test: `spec/services/image_stitcher_spec.rb`.

**Interfaces:**
- Produces: `ImageStitcher.stitch(input_dir:, output_path:)` → runs the vendored `stitch.py` against `input_dir`, writes `output_path`, returns `output_path`. Raises `RuntimeError` on nonzero exit.

- [ ] **Step 1: Vendor stitch.py + python deps**

```bash
mkdir -p vendor
git clone https://github.com/nocoo/image-stitch vendor/image-stitch
rm -rf vendor/image-stitch/.git
python3 -m venv python_env
./python_env/bin/pip install --upgrade pip
./python_env/bin/pip install -r vendor/image-stitch/requirements.txt
./python_env/bin/pip freeze | grep -iE "opencv|numpy" > requirements.txt
```

Verify the script runs:

```bash
./python_env/bin/python vendor/image-stitch/stitch.py --help
```

Expected: usage text mentioning `-i/--input` and `-o/--output`.

- [ ] **Step 2: Write failing spec**

`spec/services/image_stitcher_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ImageStitcher do
  it "invokes stitch.py with input dir and output path" do
    cmd_seen = nil
    allow(Open3).to receive(:popen2e) do |*cmd, &blk|
      cmd_seen = cmd
      blk.call(nil, StringIO.new("ok"), double(value: double(success?: true)))
    end

    out = ImageStitcher.stitch(input_dir: "/tmp/pre", output_path: "/tmp/out.png")
    expect(out).to eq("/tmp/out.png")
    expect(cmd_seen).to include("-i", "/tmp/pre", "-o", "/tmp/out.png")
    expect(cmd_seen.join(" ")).to include("stitch.py")
  end

  it "raises on failure" do
    allow(Open3).to receive(:popen2e) do |*_cmd, &blk|
      blk.call(nil, StringIO.new("crash"), double(value: double(success?: false)))
    end
    expect { ImageStitcher.stitch(input_dir: "/tmp/pre", output_path: "/tmp/out.png") }
      .to raise_error(RuntimeError, /stitch failed/)
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
bundle exec rspec spec/services/image_stitcher_spec.rb
```

Expected: FAIL (`uninitialized constant ImageStitcher`).

- [ ] **Step 4: Implement**

`app/services/image_stitcher.rb`:

```ruby
require "open3"

class ImageStitcher
  PYTHON = Rails.root.join("python_env/bin/python").to_s
  SCRIPT = Rails.root.join("vendor/image-stitch/stitch.py").to_s

  def self.stitch(input_dir:, output_path:)
    cmd = [PYTHON, SCRIPT, "-i", input_dir.to_s, "-o", output_path.to_s]
    Rails.logger.debug("[Stitch] #{cmd.join(' ')}")
    Open3.popen2e(*cmd) do |_in, out, wait|
      output = out.read
      raise "stitch failed: #{output}" unless wait.value.success?
      Rails.logger.debug("[Stitch] #{output}")
    end
    output_path.to_s
  end
end
```

- [ ] **Step 5: Run to verify pass**

```bash
bundle exec rspec spec/services/image_stitcher_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A vendor/image-stitch requirements.txt app/services/image_stitcher.rb spec/services/image_stitcher_spec.rb
git commit -m "feat: vendor image-stitch and add ImageStitcher service"
```

---

### Task 8: OcrClient (OpenAI vision)

**Files:**
- Create: `app/services/ocr_client.rb`.
- Test: `spec/services/ocr_client_spec.rb`.

**Interfaces:**
- Produces: `OcrClient.extract(image_path:)` → reads image, base64-encodes, POSTs to OpenAI chat completions with the extraction prompt + image, parses the response into an Array of transaction hashes (string keys: `date`, `description`, `bank_name`, `merchant`, `cardname`, `amount`, `category`). Strips stray markdown fences. Raises on non-success HTTP or unparseable JSON.

- [ ] **Step 1: Write failing spec**

`spec/services/ocr_client_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe OcrClient do
  let(:img) { Rails.root.join("tmp/ocr_test.png") }
  before do
    FileUtils.mkdir_p(Rails.root.join("tmp"))
    File.binwrite(img, "imgbytes")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
    allow(ENV).to receive(:[]).with("OPENAI_MODEL").and_return("gpt-5.4-nano-2026-03-17")
  end
  after { FileUtils.rm_f(img) }

  it "parses the JSON array from the model response" do
    content = '[{"date":"2025-10-12","description":"COFFEE","bank_name":"unknown","merchant":"Starbucks","cardname":"unknown","amount":-4.5,"category":"Food"}]'
    body = { "choices" => [{ "message" => { "content" => content } }] }.to_json
    fake_resp = double(status: double(success?: true), to_s: body)
    fake_http = double
    allow(HTTP).to receive(:auth).with("Bearer sk-test").and_return(fake_http)
    allow(fake_http).to receive(:post).and_return(fake_resp)

    result = OcrClient.extract(image_path: img)
    expect(result.first["merchant"]).to eq("Starbucks")
    expect(result.first["amount"]).to eq(-4.5)
  end

  it "strips markdown fences before parsing" do
    content = "```json\n[{\"date\":\"2025-10-12\",\"description\":\"X\",\"amount\":-1.0}]\n```"
    body = { "choices" => [{ "message" => { "content" => content } }] }.to_json
    fake_resp = double(status: double(success?: true), to_s: body)
    fake_http = double
    allow(HTTP).to receive(:auth).and_return(fake_http)
    allow(fake_http).to receive(:post).and_return(fake_resp)
    expect(OcrClient.extract(image_path: img).first["description"]).to eq("X")
  end

  it "raises on HTTP failure" do
    fake_resp = double(status: double(success?: false), to_s: "err")
    fake_http = double
    allow(HTTP).to receive(:auth).and_return(fake_http)
    allow(fake_http).to receive(:post).and_return(fake_resp)
    expect { OcrClient.extract(image_path: img) }.to raise_error(RuntimeError, /OCR request failed/)
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/ocr_client_spec.rb
```

Expected: FAIL (`uninitialized constant OcrClient`).

- [ ] **Step 3: Implement**

`app/services/ocr_client.rb`:

```ruby
class OcrClient
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  PROMPT = <<~TXT.freeze
    You are an expert data extraction assistant. Your task is to analyze the provided screenshot of bank transactions and extract all line items into a clean, structured format.

    ### Instructions:
    1. Extract every unique transaction visible in the image.
    2. De-duplicate: The image may show the same transaction multiple times. Only record each unique transaction once.
    3. If a transaction is partially cut off at the very beginning or end of image video and the details are illegible, omit it.
    4. Convert all shorthand month names to standard full dates if the year is known (e.g., "Oct 12" -> "2025-10-12"). If the year is not visible, default to the current year 2026.

    ### Output Format:
    Provide the output strictly as a valid JSON array of objects (which I will convert to CSV). Do not include any conversational text, markdown formatting blocks (like ```json), or explanations.
    - "date": YYYY-MM-DD format
    - "description": The text description or vendor name
    - "bank_name": infer the name of the bank from the UI, if not sure output 'unknown'
    - "merchant": the name of the merchant if available otherwise 'unknown'
    - "cardname": infer the name of the credit card from the UI, if not sure output 'unknown'
    - "amount": The amount as a float (negative for expenditures/debits, positive for income/credits)
    - "category": A best-guess category based on the vendor name (e.g., Food, Utilities, Transport, Shopping)
  TXT

  def self.extract(image_path:)
    b64 = Base64.strict_encode64(File.binread(image_path))
    payload = {
      model: ENV["OPENAI_MODEL"],
      messages: [{
        role: "user",
        content: [
          { type: "text", text: PROMPT },
          { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}" } }
        ]
      }]
    }
    Rails.logger.debug("[OCR] posting #{image_path} to OpenAI model #{ENV['OPENAI_MODEL']}")
    resp = HTTP.auth("Bearer #{ENV['OPENAI_API_KEY']}").post(ENDPOINT, json: payload)
    raise "OCR request failed: #{resp.to_s}" unless resp.status.success?

    content = JSON.parse(resp.to_s).dig("choices", 0, "message", "content").to_s
    cleaned = content.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "").strip
    parsed = JSON.parse(cleaned)
    raise "OCR returned non-array" unless parsed.is_a?(Array)
    parsed
  end
end
```

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rspec spec/services/ocr_client_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add OcrClient calling OpenAI vision via http gem"
```

---

### Task 9: TransactionImporter + IngestJob orchestration

**Files:**
- Create: `app/services/transaction_importer.rb`.
- Modify: `app/jobs/ingest_job.rb`.
- Test: `spec/services/transaction_importer_spec.rb`, `spec/jobs/ingest_job_spec.rb`.

**Interfaces:**
- Consumes: `ImagePreprocessor.process`, `ImageStitcher.stitch`, `OcrClient.extract`, `Transaction.dedup_create!`, `SlackNotifier.notify`, `IngestController.batch_dir`.
- Produces:
  - `TransactionImporter.import(batch:, rows:)` → for each row hash, `Transaction.dedup_create!`; returns count created.
  - `IngestJob#perform(batch_id)` → marks batch `processing`; preprocess → stitch → ocr → import; marks `completed`; cleans temp dirs. On any error: `batch.fail!(msg)`, `SlackNotifier.notify`, re-raise.

- [ ] **Step 1: Write failing TransactionImporter spec**

`spec/services/transaction_importer_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe TransactionImporter do
  it "creates deduped transactions and returns count" do
    batch = Batch.create!
    rows = [
      { "date" => "2025-10-12", "description" => "COFFEE", "amount" => -4.5, "merchant" => "SB", "category" => "Food" },
      { "date" => "2025-10-12", "description" => "COFFEE", "amount" => -4.5, "merchant" => "SB", "category" => "Food" }
    ]
    expect(TransactionImporter.import(batch: batch, rows: rows)).to eq(1)
    expect(batch.transactions.count).to eq(1)
  end
end
```

- [ ] **Step 2: Run to verify failure, then implement**

```bash
bundle exec rspec spec/services/transaction_importer_spec.rb
```

Expected: FAIL. Then create `app/services/transaction_importer.rb`:

```ruby
class TransactionImporter
  PERMITTED = %w[date description bank_name merchant cardname amount category].freeze

  def self.import(batch:, rows:)
    created = 0
    rows.each do |row|
      attrs = row.slice(*PERMITTED)
      next if attrs["date"].blank? || attrs["amount"].nil?
      created += 1 if Transaction.dedup_create!(batch: batch, attrs: attrs)
    end
    Rails.logger.debug("[Import] created #{created} transactions for batch #{batch.id}")
    created
  end
end
```

Run again, expect PASS.

- [ ] **Step 3: Write failing IngestJob spec**

`spec/jobs/ingest_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe IngestJob do
  let(:batch) { Batch.create! }
  before do
    FileUtils.mkdir_p(IngestController.batch_dir(batch.id))
    File.binwrite(IngestController.batch_dir(batch.id).join("000.png"), "x")
  end
  after { FileUtils.rm_rf(IngestController.batch_dir(batch.id)) }

  it "runs the pipeline and completes the batch" do
    allow(ImagePreprocessor).to receive(:process).and_return(["/tmp/pre/000.png"])
    allow(ImageStitcher).to receive(:stitch).and_return("/tmp/stitched.png")
    allow(OcrClient).to receive(:extract).and_return(
      [{ "date" => "2025-10-12", "description" => "COFFEE", "amount" => -4.5 }]
    )

    IngestJob.perform_now(batch.id)

    expect(batch.reload).to be_completed
    expect(batch.transactions.count).to eq(1)
  end

  it "fails the batch and notifies Slack on error" do
    allow(ImagePreprocessor).to receive(:process).and_raise("magick boom")
    expect(SlackNotifier).to receive(:notify).with(/magick boom/)

    expect { IngestJob.perform_now(batch.id) }.to raise_error(/magick boom/)
    expect(batch.reload).to be_failed
    expect(batch.error_message).to match(/magick boom/)
  end
end
```

- [ ] **Step 4: Run to verify failure**

```bash
bundle exec rspec spec/jobs/ingest_job_spec.rb
```

Expected: FAIL (job is a no-op stub).

- [ ] **Step 5: Implement IngestJob**

`app/jobs/ingest_job.rb`:

```ruby
class IngestJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    batch = Batch.find(batch_id)
    batch.processing!
    Rails.logger.debug("[IngestJob] start batch #{batch_id}")

    input_dir = IngestController.batch_dir(batch_id)
    pre_dir = Rails.root.join("tmp/ingest", "#{batch_id}_pre")
    stitched = Rails.root.join("tmp/ingest", "#{batch_id}_stitched.png")
    FileUtils.mkdir_p(pre_dir)

    ImagePreprocessor.process(input_dir: input_dir, output_dir: pre_dir)
    ImageStitcher.stitch(input_dir: pre_dir, output_path: stitched)
    rows = OcrClient.extract(image_path: stitched)
    TransactionImporter.import(batch: batch, rows: rows)

    batch.completed!
    Rails.logger.debug("[IngestJob] completed batch #{batch_id}")
  rescue => e
    Rails.logger.error("[IngestJob] batch #{batch_id} failed: #{e.message}")
    batch&.fail!(e.message)
    SlackNotifier.notify("IngestJob failed for batch #{batch_id}: #{e.message}")
    raise
  ensure
    FileUtils.rm_rf(input_dir) if defined?(input_dir) && input_dir
    FileUtils.rm_rf(pre_dir) if defined?(pre_dir) && pre_dir
    FileUtils.rm_f(stitched) if defined?(stitched) && stitched
  end
end
```

- [ ] **Step 6: Run to verify pass**

```bash
bundle exec rspec spec/jobs/ingest_job_spec.rb spec/services/transaction_importer_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: implement IngestJob pipeline and TransactionImporter"
```

---

### Task 10: DashboardStats query object

**Files:**
- Create: `app/services/dashboard_stats.rb`.
- Test: `spec/services/dashboard_stats_spec.rb`.

**Interfaces:**
- Produces: `DashboardStats.new.to_h` → hash with keys:
  - `top_categories`: array (<=5) of `{ category:, total:, percentage: }`, sorted desc by total spend; percentage of overall spend.
  - `top_merchants`: array (<=5) of `{ merchant:, total: }`, sorted desc.
  - `largest_purchases`: array (<=5) of `{ date:, merchant:, amount: }`, most negative first.
  - `category_timeseries`: `{ months: [YYYY-MM,...], series: [{ category:, data: [..] }] }` spend per category per month.
  - All "spend" uses `abs(amount)` where `amount < 0`.

- [ ] **Step 1: Write failing spec**

`spec/services/dashboard_stats_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe DashboardStats do
  let(:batch) { Batch.create! }
  before do
    batch.transactions.create!(date: "2025-10-01", description: "A", merchant: "Store1", amount: -100, category: "Food")
    batch.transactions.create!(date: "2025-10-02", description: "B", merchant: "Store2", amount: -300, category: "Shopping")
    batch.transactions.create!(date: "2025-11-01", description: "C", merchant: "Store1", amount: -100, category: "Food")
    batch.transactions.create!(date: "2025-11-02", description: "D", merchant: "Boss",   amount:  500, category: "Income")
  end

  let(:stats) { DashboardStats.new.to_h }

  it "computes top categories with percentages of total spend" do
    cats = stats[:top_categories]
    shopping = cats.find { |c| c[:category] == "Shopping" }
    expect(shopping[:total]).to eq(300.0)
    expect(shopping[:percentage]).to eq(60.0) # 300 of 500 total spend
  end

  it "computes top merchants by spend" do
    expect(stats[:top_merchants].first).to eq({ merchant: "Store2", total: 300.0 })
  end

  it "lists largest single purchases most-negative first" do
    expect(stats[:largest_purchases].first[:amount]).to eq(-300.0)
  end

  it "builds a category timeseries by month" do
    expect(stats[:category_timeseries][:months]).to eq(["2025-10", "2025-11"])
    food = stats[:category_timeseries][:series].find { |s| s[:category] == "Food" }
    expect(food[:data]).to eq([100.0, 100.0])
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/dashboard_stats_spec.rb
```

Expected: FAIL (`uninitialized constant DashboardStats`).

- [ ] **Step 3: Implement**

`app/services/dashboard_stats.rb`:

```ruby
class DashboardStats
  def initialize(scope = Transaction.all)
    @spend = scope.where("amount < 0")
  end

  def to_h
    {
      top_categories: top_categories,
      top_merchants: top_merchants,
      largest_purchases: largest_purchases,
      category_timeseries: category_timeseries
    }
  end

  private

  def total_spend
    @total_spend ||= @spend.sum("ABS(amount)").to_f
  end

  def top_categories
    @spend.group(:category).sum("ABS(amount)").sort_by { |_, v| -v }.first(5).map do |category, total|
      pct = total_spend.zero? ? 0.0 : (total.to_f / total_spend * 100).round(2)
      { category: category, total: total.to_f, percentage: pct }
    end
  end

  def top_merchants
    @spend.group(:merchant).sum("ABS(amount)").sort_by { |_, v| -v }.first(5).map do |merchant, total|
      { merchant: merchant, total: total.to_f }
    end
  end

  def largest_purchases
    @spend.order(:amount).limit(5).map do |t|
      { date: t.date.to_s, merchant: t.merchant, amount: t.amount.to_f }
    end
  end

  def category_timeseries
    rows = @spend.group(Arel.sql("to_char(date, 'YYYY-MM')"), :category).sum("ABS(amount)")
    months = rows.keys.map(&:first).uniq.sort
    categories = rows.keys.map(&:last).uniq
    series = categories.map do |category|
      data = months.map { |m| (rows[[m, category]] || 0).to_f }
      { category: category, data: data }
    end
    { months: months, series: series }
  end
end
```

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rspec spec/services/dashboard_stats_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add DashboardStats aggregation query object"
```

---

### Task 11: Health endpoint

**Files:**
- Create: `app/controllers/health_controller.rb`.
- Modify: `config/routes.rb`.
- Test: `spec/requests/health_spec.rb`.

**Interfaces:**
- Produces: `GET /health` → `200` + `{ status: "ok", checks: {...} }` only if DB connects, solid_queue tables queryable, and `OPENAI_API_KEY` present; else `503` + failing checks.

- [ ] **Step 1: Write failing spec**

`spec/requests/health_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GET /health" do
  before { allow(ENV).to receive(:[]).and_call_original }

  it "returns 200 when all dependencies are healthy" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-x")
    get "/health"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["status"]).to eq("ok")
  end

  it "returns 503 when OPENAI_API_KEY is missing" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
    get "/health"
    expect(response).to have_http_status(:service_unavailable)
    expect(JSON.parse(response.body)["checks"]["openai_key"]).to eq(false)
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/requests/health_spec.rb
```

Expected: FAIL (no route).

- [ ] **Step 3: Add route + controller**

In `config/routes.rb`:

```ruby
get "/health", to: "health#show"
```

`app/controllers/health_controller.rb`:

```ruby
class HealthController < ActionController::API
  def show
    checks = {
      database: database_ok?,
      solid_queue: solid_queue_ok?,
      openai_key: ENV["OPENAI_API_KEY"].present?
    }
    ok = checks.values.all?
    render json: { status: ok ? "ok" : "degraded", checks: checks },
           status: ok ? :ok : :service_unavailable
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue
    false
  end

  def solid_queue_ok?
    SolidQueue::Job.connection.execute("SELECT 1 FROM solid_queue_jobs LIMIT 1")
    true
  rescue
    false
  end
end
```

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rspec spec/requests/health_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add /health endpoint with dependency checks"
```

---

### Task 12: Inertia + React + Vite + Tailwind dashboard

**Files:**
- Modify: `Gemfile` (already has inertia_rails, vite_rails), `config/routes.rb`, `package.json`.
- Create: `app/frontend/entrypoints/application.jsx`, `app/frontend/pages/Dashboard.jsx`, `app/frontend/components/*`, `app/controllers/dashboard_controller.rb`, `app/views/layouts/application.html.erb` (Inertia root), `vite.config.ts`, Tailwind config.
- Test: `spec/requests/dashboard_spec.rb`.

**Interfaces:**
- Consumes: `DashboardStats`.
- Produces: `GET /` renders Inertia page `Dashboard` with props `{ top_categories, top_merchants, largest_purchases, category_timeseries }`; React renders Chart.js pie/bar/stacked-bar + a list. No auth.

- [ ] **Step 1: Install Vite + Inertia + React + Tailwind toolchain**

```bash
bundle exec vite install
npm install @inertiajs/react react react-dom chart.js react-chartjs-2
npm install -D @vitejs/plugin-react tailwindcss @tailwindcss/vite
```

In `vite.config.ts`, enable React + Tailwind:

```ts
import { defineConfig } from "vite"
import RubyPlugin from "vite-plugin-ruby"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"

export default defineConfig({
  plugins: [RubyPlugin(), react(), tailwindcss()],
})
```

- [ ] **Step 2: Wire Inertia + React entrypoint**

`app/frontend/entrypoints/application.jsx`:

```jsx
import { createInertiaApp } from "@inertiajs/react"
import { createRoot } from "react-dom/client"
import "../styles/application.css"

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob("../pages/**/*.jsx", { eager: true })
    return pages[`../pages/${name}.jsx`]
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
```

`app/frontend/styles/application.css`:

```css
@import "tailwindcss";
```

Configure Inertia in `config/initializers/inertia_rails.rb`:

```ruby
InertiaRails.configure do |config|
  config.version = ViteRuby.digest
end
```

Root layout `app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>bank-app-parser</title>
    <%= csrf_meta_tags %>
    <%= vite_client_tag %>
    <%= vite_javascript_tag "application" %>
  </head>
  <body><%= yield %></body>
</html>
```

- [ ] **Step 3: Write failing request spec**

`spec/requests/dashboard_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GET /" do
  it "renders the Dashboard Inertia component with stats props" do
    batch = Batch.create!
    batch.transactions.create!(date: "2025-10-01", description: "A", merchant: "Store1", amount: -100, category: "Food")

    get "/", headers: { "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["component"]).to eq("Dashboard")
    expect(json["props"]).to have_key("top_categories")
    expect(json["props"]).to have_key("category_timeseries")
  end
end
```

- [ ] **Step 4: Run to verify failure**

```bash
bundle exec rspec spec/requests/dashboard_spec.rb
```

Expected: FAIL (no route/controller).

- [ ] **Step 5: Add route + controller**

In `config/routes.rb`:

```ruby
root "dashboard#index"
```

`app/controllers/dashboard_controller.rb`:

```ruby
class DashboardController < ApplicationController
  def index
    render inertia: "Dashboard", props: DashboardStats.new.to_h
  end
end
```

- [ ] **Step 6: Build the React page**

`app/frontend/pages/Dashboard.jsx`:

```jsx
import { Chart as ChartJS, ArcElement, BarElement, CategoryScale, LinearScale, Tooltip, Legend } from "chart.js"
import { Pie, Bar } from "react-chartjs-2"

ChartJS.register(ArcElement, BarElement, CategoryScale, LinearScale, Tooltip, Legend)

const COLORS = ["#2563eb", "#16a34a", "#dc2626", "#d97706", "#7c3aed", "#0891b2"]

export default function Dashboard({ top_categories, top_merchants, largest_purchases, category_timeseries }) {
  const pieData = {
    labels: top_categories.map((c) => `${c.category} (${c.percentage}%)`),
    datasets: [{ data: top_categories.map((c) => c.total), backgroundColor: COLORS }],
  }
  const merchantData = {
    labels: top_merchants.map((m) => m.merchant),
    datasets: [{ label: "Spend", data: top_merchants.map((m) => m.total), backgroundColor: COLORS[0] }],
  }
  const tsData = {
    labels: category_timeseries.months,
    datasets: category_timeseries.series.map((s, i) => ({
      label: s.category, data: s.data, backgroundColor: COLORS[i % COLORS.length],
    })),
  }
  const stacked = { scales: { x: { stacked: true }, y: { stacked: true } } }

  return (
    <div className="mx-auto max-w-5xl p-6 space-y-10">
      <h1 className="text-2xl font-bold">Spending Overview</h1>

      <section>
        <h2 className="mb-2 font-semibold">Top Categories</h2>
        <div className="max-w-md"><Pie data={pieData} /></div>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Top Merchants</h2>
        <Bar data={merchantData} />
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Largest Purchases</h2>
        <ul className="divide-y">
          {largest_purchases.map((p, i) => (
            <li key={i} className="flex justify-between py-1">
              <span>{p.date} — {p.merchant}</span>
              <span className="font-mono">{p.amount.toFixed(2)}</span>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Spend by Category Over Time</h2>
        <Bar data={tsData} options={stacked} />
      </section>
    </div>
  )
}
```

- [ ] **Step 7: Run request spec + build assets to verify**

```bash
bundle exec rspec spec/requests/dashboard_spec.rb
npm run build || bin/vite build
```

Expected: spec PASS; Vite build succeeds with no errors.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add Inertia+React dashboard with Chart.js visualizations"
```

---

### Task 13: serve-dev script, README, CLAUDE.md

**Files:**
- Create: `serve-dev`, `README.md`, `CLAUDE.md`.

**Interfaces:**
- Produces: an executable dev launcher and project docs.

- [ ] **Step 1: Create serve-dev**

`serve-dev`:

```bash
#!/bin/bash
set -a
[ -f .env ] && . .env
set +a

SESSION="bank_app_parser"
tmux kill-session -t "$SESSION" 2>/dev/null

tmux new-session -d -s "$SESSION" -n main
tmux split-window -h -t "$SESSION"
tmux split-window -v -t "$SESSION"

# Pane 0: Vite dev server (HMR + Tailwind regeneration)
tmux send-keys -t "$SESSION:main.0" "source .env && bin/vite dev" C-m
# Pane 1: Rails server
tmux send-keys -t "$SESSION:main.1" "source .env && bin/rails s -p \$RAILS_PORT -b 0.0.0.0" C-m
# Pane 2: Solid Queue worker (logs to STDOUT)
tmux send-keys -t "$SESSION:main.2" "source .env && RAILS_LOG_TO_STDOUT=1 bin/rails solid_queue:start" C-m

tmux attach -t "$SESSION"
```

```bash
chmod +x serve-dev
```

- [ ] **Step 2: Write README.md**

Create `README.md` covering: purpose (ingest bank screenshots → analyze spending); architecture (ingest endpoint → solid_queue IngestJob → preprocess/stitch/OCR → transactions → Inertia dashboard); prerequisites (rbenv Ruby 3.4.7, Postgres 18, ImageMagick `magick`, Python3 for `./python_env`, tmux, node); setup steps:

```bash
rbenv local 3.4.7
bundle install
python3 -m venv python_env && ./python_env/bin/pip install -r requirements.txt
npm install
cp .env.example .env   # fill in OPENAI_API_KEY, INGEST_TOKEN, SLACK_WEBHOOK_URL
bin/rails db:create db:migrate
./serve-dev
```

…plus env var table, and a sample `curl -X POST -H "Authorization: Bearer $INGEST_TOKEN" -F images[]=@a.png -F images[]=@b.png localhost:3000/ingest`.

- [ ] **Step 3: Write CLAUDE.md**

Create `CLAUDE.md` with: project summary; commands (`bundle exec rspec`, `./serve-dev`, `bin/rails db:migrate`); architecture map (controllers/jobs/services list with one-line responsibilities); conventions (Ruby 3.4.7, RSpec, services are plain classes with class methods, `http` gem for HTTP, ImageMagick via `magick`, Python stitch via `./python_env`); env vars; "spend = abs(amount) where amount < 0".

- [ ] **Step 4: Full suite + commit**

```bash
bundle exec rspec
git add -A
git commit -m "docs: add serve-dev launcher, README, and CLAUDE.md"
```

Expected: full suite green.

---

## Self-Review

**Spec coverage:**
- Ingest endpoint + background job + env token auth → Task 5. ✓
- Preprocess (resize <768 keep aspect, greyscale) → Task 6. ✓
- Stitch via nocoo/image-stitch + Open3.popen2e → Task 7. ✓
- ImageMagick assumed available → Tasks 6 (uses `magick`), README prereqs Task 13. ✓
- OCR via OpenAI w/ exact prompt + model from env → Task 8. ✓
- Post-OCR create transactions → Task 9. ✓
- Dashboard 4 visualizations, no auth → Tasks 10 + 12. ✓
- Ruby 3.4.7, .ruby-version, Gemfile pin → Task 1. ✓
- Robust .gitignore → Task 1. ✓
- Postgres 3 DBs, unified schema, PG cache + solid_queue in primary schema → Tasks 1 + 2. ✓
- RSpec replaces Minitest → Task 1. ✓
- /health checks DB + services → Task 11. ✓
- Libraries: dotenv, http, inertia_rails, tailwind, chartjs → Tasks 1, 8, 12. ✓
- Vite build + autoreload, Tailwind regen, jobs→STDOUT, debug logs each step → Tasks 2, 6–9, 12. ✓
- serve-dev tmux script → Task 13. ✓
- README + CLAUDE.md → Task 13. ✓
- SlackNotifier on OCR/job failure → Tasks 4 + 9. ✓
- Uploads to temp dir (not ActiveStorage) → Task 5. ✓

**Placeholder scan:** No TBD/TODO; all code steps contain concrete code. README/CLAUDE.md content is enumerated (acceptable: doc prose, not code).

**Type consistency:** `IngestController.batch_dir`, `Batch#fail!`, `Transaction.dedup_create!`, `DashboardStats#to_h` keys, service signatures (`process`, `stitch`, `extract`, `import`) consistent across Tasks 5–12. ✓
