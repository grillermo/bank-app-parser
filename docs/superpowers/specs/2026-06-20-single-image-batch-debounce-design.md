# Single-Image Ingest with Debounced Batch Processing — Design

## Purpose
Change `/ingest` from accepting an array of images per request (one batch per request) to
accepting one image per request, appended to the most recent pending batch. Batch processing
is debounced: each new image delays processing by 15 minutes, so a batch only processes after
15 minutes of inactivity. Only one `IngestJob` may execute at a time across the whole app.

## Data Model

Migration adds to `batches`:
- `next_image_index` (integer, default 0, null: false) — atomic counter for the zero-padded
  filename index (`%03d.png`). Needed because `ImageStitcher`'s underlying Python script sorts
  files lexically by filename to reconstruct multi-screenshot order
  (`vendor/image-stitch/stitch.py:311-312`), so filenames must encode insertion order.
- `scheduled_job_id` (string, nullable) — the ActiveJob `job_id` of the currently scheduled
  `IngestJob` for this batch, so a new image can cancel and reschedule it.
- Partial unique index on `status` where `status = 0` (pending) — guarantees at most one pending
  batch exists at the DB level, even under concurrent requests.

## Controller Flow (`IngestController#create`)

1. Accept `params[:image]` (single uploaded file, not an array). Render 422 if blank.
2. `find_or_create_pending_batch`:
   ```ruby
   Batch.where(status: :pending).order(created_at: :desc).first || Batch.create!
   ```
   Rescue `ActiveRecord::RecordNotUnique` (from the partial unique index) by re-querying for the
   pending batch — a concurrent request may have just created it.
3. Inside `batch.with_lock` (row lock via `SELECT ... FOR UPDATE`):
   - Write the file to `IngestController.batch_dir(batch.id)` as
     `format("%03d.png", batch.next_image_index)`.
   - If `batch.scheduled_job_id` is present, look up and cancel the previously scheduled job:
     ```ruby
     SolidQueue::Job.find_by(active_job_id: batch.scheduled_job_id)&.discard
     ```
     Rescue `SolidQueue::Execution::UndiscardableError` — raised if the job has already been
     claimed/started running. In that case, skip rescheduling; the in-flight job will process
     whatever's already on disk in `batch_dir` at the time it reads it. This is a narrow,
     accepted race window given manual/low-frequency usage.
   - Enqueue a new job: `IngestJob.set(wait: 15.minutes).perform_later(batch.id)`.
   - Persist `next_image_index: index + 1` and `scheduled_job_id: job.job_id` on the batch.
4. Respond `{ batch_id: batch.id, status: batch.status }` with `202 Accepted` (unchanged from
   current behavior).

## Job Execution Concurrency (`IngestJob`)

Add Solid Queue's native single-flight guard:
```ruby
limits_concurrency to: 1, key: "ingest_job", duration: 30.minutes
```
- `duration: 30.minutes` overrides Solid Queue's 3-minute default, which is too short to cover
  preprocess + stitch + OpenAI vision OCR for a single batch.
- Default `on_conflict: :block` is used: if another `IngestJob` is already running when this
  one's `scheduled_at` arrives, it waits (blocked execution) until the running one finishes,
  rather than erroring or running concurrently.
- No changes to `IngestJob#perform` body — it already reads whatever's in `batch_dir` at
  execution time, so it works unmodified with batches that accumulated multiple images over
  the debounce window.

## Failure Handling
No change from current behavior: `IngestJob`'s existing `ensure` block cleans up temp files,
`rescue` sets `batch.fail!(message)` and notifies Slack. A failed batch is no longer `pending`,
so subsequent images create a new batch rather than reusing it.

## Out of Scope
- No enforcement of a max images-per-batch or max debounce-extension count.
- No UI/API change beyond the `/ingest` request shape (`image` singular).
- No retry/backoff changes to `IngestJob` itself.
