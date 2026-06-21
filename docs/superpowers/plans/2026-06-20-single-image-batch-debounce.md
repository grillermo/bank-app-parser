# Single-Image Ingest with Debounced Batch Processing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change `/ingest` to accept one image per request, append it to the most recent pending batch, debounce batch processing by 15 minutes per new image, and guarantee only one `IngestJob` ever runs at a time.

**Architecture:** A DB-level partial unique index guarantees at most one pending `Batch` exists. `Batch.find_or_create_pending!` finds or atomically creates it (via Rails' `create_or_find_by!` race-safe idiom). `Batch#append_image!` writes the image under a row lock and delegates job scheduling to a new `BatchScheduler` service, which cancels any previously-scheduled `IngestJob` for that batch and enqueues a new one 15 minutes out — unless the old job has already been claimed by a worker, in which case it leaves the in-flight job alone. `IngestJob` gets Solid Queue's native `limits_concurrency` guard so only one instance executes at a time app-wide.

**Tech Stack:** Rails 8 / Ruby 3.4.7, RSpec, Solid Queue (Active Job backend), PostgreSQL 18 (partial unique index).

**Spec:** `docs/superpowers/specs/2026-06-20-single-image-batch-debounce-design.md`

---

## File Structure

- Create: `db/migrate/<timestamp>_add_debounce_fields_to_batches.rb` — adds `next_image_index`, `scheduled_job_id`, partial unique index on pending status
- Modify: `app/models/batch.rb` — add `find_or_create_pending!`, `append_image!`
- Create: `app/services/batch_scheduler.rb` — cancel/enqueue debounce logic for a batch's `IngestJob`
- Modify: `app/jobs/ingest_job.rb` — add `limits_concurrency`
- Modify: `app/controllers/ingest_controller.rb` — single-image param, delegate to `Batch`
- Modify: `spec/models/batch_spec.rb` — cover new `Batch` methods
- Create: `spec/services/batch_scheduler_spec.rb` — cover `BatchScheduler`
- Modify: `spec/jobs/ingest_job_spec.rb` — cover concurrency config
- Modify: `spec/requests/ingest_spec.rb` — cover new single-image, debounce, append behavior

---

## Chunk 1: Migration, Batch model, BatchScheduler, IngestJob, Controller

### Task 1: Migration — debounce columns and single-pending-batch constraint

**Files:**
- Create: `db/migrate/<timestamp>_add_debounce_fields_to_batches.rb` (use `bin/rails generate migration AddDebounceFieldsToBatches` to get a real timestamp)

- [ ] **Step 1: Generate the migration**

Run: `RAILS_ENV=development bin/rails generate migration AddDebounceFieldsToBatches`
Expected: creates `db/migrate/<timestamp>_add_debounce_fields_to_batches.rb`

- [ ] **Step 2: Write the migration**

```ruby
class AddDebounceFieldsToBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :batches, :next_image_index, :integer, null: false, default: 0
    add_column :batches, :scheduled_job_id, :string

    add_index :batches, :status,
      unique: true,
      where: "status = 0",
      name: "index_batches_on_single_pending"
  end
end
```

- [ ] **Step 3: Run the migration and confirm schema.rb updated**

Run: `RAILS_ENV=development bin/rails db:migrate`
Expected: migration runs successfully; `db/schema.rb` now shows `next_image_index`, `scheduled_job_id` columns on `batches`, and the `index_batches_on_single_pending` partial unique index.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_add_debounce_fields_to_batches.rb db/schema.rb
git commit -m "feat: add debounce fields and single-pending-batch constraint"
```

---

### Task 2: `Batch.find_or_create_pending!`

**Files:**
- Modify: `app/models/batch.rb`
- Test: `spec/models/batch_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/batch_spec.rb`:

```ruby
describe ".find_or_create_pending!" do
  it "returns the existing pending batch instead of creating a new one" do
    pending_batch = Batch.create!
    expect { Batch.find_or_create_pending! }.not_to change(Batch, :count)
    expect(Batch.find_or_create_pending!).to eq(pending_batch)
  end

  it "creates a new batch when none is pending" do
    expect { Batch.find_or_create_pending! }.to change(Batch, :count).by(1)
    expect(Batch.find_or_create_pending!.status).to eq("pending")
  end

  it "never allows two pending batches to exist (DB constraint)" do
    Batch.create!(status: :pending)
    expect { Batch.create!(status: :pending) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/batch_spec.rb -e "find_or_create_pending!"`
Expected: FAIL — `NoMethodError: undefined method 'find_or_create_pending!'` for the first two; the third should already pass once the Task 1 migration is applied (confirms the constraint independently of any new code).

- [ ] **Step 3: Implement**

In `app/models/batch.rb`, add inside the class:

```ruby
def self.find_or_create_pending!
  where(status: :pending).first || create_or_find_by!(status: :pending)
end
```

`create_or_find_by!` is Rails' built-in race-safe idiom: if a concurrent request already created the pending batch between our `.first` check and `create!`, the unique index raises and Rails falls back to `find_by!` to return the winner's row — no manual rescue needed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/batch_spec.rb`
Expected: PASS (all examples, including the pre-existing two from before this task)

- [ ] **Step 5: Commit**

```bash
git add app/models/batch.rb spec/models/batch_spec.rb
git commit -m "feat: add Batch.find_or_create_pending!"
```

---

### Task 3: `BatchScheduler` service

**Files:**
- Create: `app/services/batch_scheduler.rb`
- Test: `spec/services/batch_scheduler_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/batch_scheduler_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe BatchScheduler do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  let(:batch) { Batch.create! }

  describe ".reschedule!" do
    it "enqueues IngestJob 15 minutes out and stores its job_id when nothing was scheduled" do
      expect {
        BatchScheduler.reschedule!(batch)
      }.to have_enqueued_job(IngestJob).with(batch.id).at(15.minutes.from_now)

      expect(batch.reload.scheduled_job_id).to be_present
    end

    it "cancels the previously scheduled job and schedules a new one" do
      BatchScheduler.reschedule!(batch)
      first_job_id = batch.reload.scheduled_job_id

      travel 1.minute do
        BatchScheduler.reschedule!(batch)
      end

      expect(batch.reload.scheduled_job_id).to be_present
      expect(batch.scheduled_job_id).not_to eq(first_job_id)
      expect(SolidQueue::Job.find_by(active_job_id: first_job_id)).to be_nil
    end

    it "does not enqueue a replacement when the existing job has already been claimed" do
      BatchScheduler.reschedule!(batch)
      claimed_job_id = batch.reload.scheduled_job_id
      job_record = SolidQueue::Job.find_by(active_job_id: claimed_job_id)
      allow(SolidQueue::Job).to receive(:find_by).with(active_job_id: claimed_job_id).and_return(job_record)
      allow(job_record).to receive(:discard).and_raise(SolidQueue::Execution::UndiscardableError)

      expect {
        BatchScheduler.reschedule!(batch)
      }.not_to have_enqueued_job(IngestJob)

      expect(batch.reload.scheduled_job_id).to eq(claimed_job_id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/batch_scheduler_spec.rb`
Expected: FAIL — `NameError: uninitialized constant BatchScheduler`

- [ ] **Step 3: Implement**

Create `app/services/batch_scheduler.rb`:

```ruby
class BatchScheduler
  WAIT = 15.minutes

  def self.reschedule!(batch)
    return unless cancel_scheduled!(batch)

    job = IngestJob.set(wait: WAIT).perform_later(batch.id)
    batch.update!(scheduled_job_id: job.job_id)
  end

  # Returns true if it's safe to schedule a new job (nothing was scheduled,
  # or the old one was successfully cancelled). Returns false if the existing
  # job has already been claimed by a worker and must be left to run.
  def self.cancel_scheduled!(batch)
    return true if batch.scheduled_job_id.blank?

    SolidQueue::Job.find_by(active_job_id: batch.scheduled_job_id)&.discard
    true
  rescue SolidQueue::Execution::UndiscardableError
    false
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/batch_scheduler_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/batch_scheduler.rb spec/services/batch_scheduler_spec.rb
git commit -m "feat: add BatchScheduler to debounce IngestJob scheduling"
```

---

### Task 4: `Batch#append_image!`

**Files:**
- Modify: `app/models/batch.rb`
- Test: `spec/models/batch_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/batch_spec.rb`:

```ruby
require "tmpdir"

describe "#append_image!" do
  it "writes the image as a zero-padded sequential filename and advances the counter" do
    batch = Batch.create!
    Dir.mktmpdir do |dir|
      dir = Pathname.new(dir)
      batch.append_image!(StringIO.new("first"), dir: dir)
      batch.append_image!(StringIO.new("second"), dir: dir)

      expect(dir.join("000.png").read).to eq("first")
      expect(dir.join("001.png").read).to eq("second")
      expect(batch.reload.next_image_index).to eq(2)
    end
  end

  it "schedules batch processing via BatchScheduler" do
    batch = Batch.create!
    expect(BatchScheduler).to receive(:reschedule!).with(batch)

    Dir.mktmpdir do |dir|
      batch.append_image!(StringIO.new("x"), dir: Pathname.new(dir))
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/batch_spec.rb -e "append_image!"`
Expected: FAIL — `NoMethodError: undefined method 'append_image!'`

- [ ] **Step 3: Implement**

In `app/models/batch.rb`, add:

```ruby
def append_image!(io, dir:)
  with_lock do
    FileUtils.mkdir_p(dir)
    dir.join(format("%03d.png", next_image_index)).binwrite(io.read)
    BatchScheduler.reschedule!(self)
    update!(next_image_index: next_image_index + 1)
  end
end
```

Note: `with_lock` reloads the record before yielding, so `next_image_index` and
`scheduled_job_id` (read inside `BatchScheduler.reschedule!`) are always current.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/batch_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/batch.rb spec/models/batch_spec.rb
git commit -m "feat: add Batch#append_image!"
```

---

### Task 5: `IngestJob` single-flight concurrency guard

**Files:**
- Modify: `app/jobs/ingest_job.rb`
- Test: `spec/jobs/ingest_job_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/jobs/ingest_job_spec.rb`:

```ruby
describe "concurrency configuration" do
  it "limits to one running job at a time for at least the pipeline's expected duration" do
    expect(IngestJob.concurrency_limit).to eq(1)
    expect(IngestJob.concurrency_key).to eq("ingest_job")
    expect(IngestJob.concurrency_duration).to eq(30.minutes)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/ingest_job_spec.rb -e "concurrency configuration"`
Expected: FAIL — `concurrency_limit` is `nil`, not `1`

- [ ] **Step 3: Implement**

In `app/jobs/ingest_job.rb`, change:

```ruby
class IngestJob < ApplicationJob
  queue_as :default
```

to:

```ruby
class IngestJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "ingest_job", duration: 30.minutes
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/jobs/ingest_job_spec.rb`
Expected: PASS (all examples, including pre-existing pipeline tests — `perform_now` bypasses concurrency dispatch entirely, so they're unaffected)

- [ ] **Step 5: Commit**

```bash
git add app/jobs/ingest_job.rb spec/jobs/ingest_job_spec.rb
git commit -m "feat: cap IngestJob to one running instance at a time"
```

---

### Task 6: `IngestController` — single image, append-to-pending-batch

**Files:**
- Modify: `app/controllers/ingest_controller.rb`
- Test: `spec/requests/ingest_spec.rb`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `spec/requests/ingest_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe "POST /ingest", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  let(:token) { "dev-local-token" }
  before { allow(ENV).to receive(:[]).and_call_original }
  before { allow(ENV).to receive(:[]).with("INGEST_TOKEN").and_return(token) }

  def image
    Rack::Test::UploadedFile.new(StringIO.new("fakebytes"), "image/png", original_filename: "shot.png")
  end

  after { FileUtils.rm_rf(Rails.root.join("tmp/ingest")) }

  it "rejects requests without the bearer token" do
    post "/ingest", params: { image: image }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects requests with no image" do
    post "/ingest", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to eq("no image")
  end

  it "creates a batch, saves the image, and schedules processing 15 minutes out" do
    expect {
      post "/ingest", params: { image: image },
           headers: { "Authorization" => "Bearer #{token}" }
    }.to have_enqueued_job(IngestJob).at(15.minutes.from_now).and change(Batch, :count).by(1)

    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    dir = IngestController.batch_dir(body["batch_id"])
    expect(Dir.glob(dir.join("*.png"))).to eq([dir.join("000.png").to_s])
  end

  it "appends a second image to the same pending batch instead of creating a new one" do
    post "/ingest", params: { image: image }, headers: { "Authorization" => "Bearer #{token}" }
    first_batch_id = JSON.parse(response.body)["batch_id"]

    expect {
      post "/ingest", params: { image: image }, headers: { "Authorization" => "Bearer #{token}" }
    }.not_to change(Batch, :count)

    second_batch_id = JSON.parse(response.body)["batch_id"]
    expect(second_batch_id).to eq(first_batch_id)

    dir = IngestController.batch_dir(first_batch_id)
    expect(Dir.glob(dir.join("*.png")).sort).to eq(
      [dir.join("000.png").to_s, dir.join("001.png").to_s]
    )
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/ingest_spec.rb`
Expected: FAIL — old controller still expects `params[:images]` as an array, so no file gets saved and/or batch_id/dir assertions mismatch.

- [ ] **Step 3: Implement**

Replace `app/controllers/ingest_controller.rb`'s `create` method:

```ruby
def create
  file = params[:image]
  return render(json: { error: "no image" }, status: :unprocessable_entity) if file.blank?

  batch = Batch.find_or_create_pending!
  batch.append_image!(file, dir: self.class.batch_dir(batch.id))
  Rails.logger.debug("[Ingest] saved image for batch #{batch.id}, status=#{batch.status}")

  render json: { batch_id: batch.id, status: batch.status }, status: :accepted
end
```

(`batch_dir` class method and `authenticate` stay unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/ingest_spec.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — no regressions in `spec/jobs/ingest_job_spec.rb`, `spec/models/batch_spec.rb`, dashboard/service specs, etc.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/ingest_controller.rb spec/requests/ingest_spec.rb
git commit -m "feat: accept single image per /ingest request, append to pending batch"
```

---

## Manual Verification (after all tasks)

Since this changes an externally-facing API, after the full suite passes:

1. Start the dev server: `./serve-dev`
2. POST a real image to `/ingest` with `curl`:
   ```bash
   curl -X POST http://localhost:3000/ingest \
     -H "Authorization: Bearer $INGEST_TOKEN" \
     -F "image=@/path/to/screenshot.png"
   ```
3. Confirm the JSON response has a `batch_id` and `status: "pending"`.
4. POST a second image within a few seconds and confirm the response reuses the same `batch_id`.
5. Check `bin/rails console` (`RAILS_ENV=development`): `SolidQueue::Job.find_by(active_job_id: Batch.last.scheduled_job_id).scheduled_at` is ~15 minutes out from the *second* POST, not the first (debounce confirmed).
6. Either wait 15 minutes or temporarily lower `BatchScheduler::WAIT` locally to confirm `IngestJob` actually runs and completes the batch end-to-end.
