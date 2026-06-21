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

1. Accept `params[:image]` (single uploaded file, not an array). Render
   `{ error: "no image" }` with `422 Unprocessable Entity` if blank (matches the existing
   `{ error: "no images" }` convention, singularized).
2. `find_or_create_pending_batch` (single retry, not a loop — the partial unique index
   guarantees at most one pending batch exists, so a retry only ever needs to happen once: the
   loser of a create race simply finds the winner's row on the next query):
   ```ruby
   def find_or_create_pending_batch
     Batch.where(status: :pending).first || Batch.create!
   rescue ActiveRecord::RecordNotUnique
     Batch.where(status: :pending).first!
   end
   ```
   (No `order` needed — the unique index means there's at most one match.)
3. Inside `batch.with_lock` (row lock via `SELECT ... FOR UPDATE`; this is a *separate* guard
   from the partial unique index above — the index prevents two *pending batches* from existing,
   `with_lock` serializes concurrent *appends to the same batch* and guarantees a fresh reload of
   `next_image_index`/`scheduled_job_id` before they're read):
   - Write the file to `IngestController.batch_dir(batch.id)` as
     `format("%03d.png", batch.next_image_index)`.
   - If `batch.scheduled_job_id` is present, attempt to cancel the previously scheduled job:
     ```ruby
     SolidQueue::Job.find_by(active_job_id: batch.scheduled_job_id)&.discard
     ```
     - **If discard succeeds (or there was nothing to cancel):** enqueue a new job —
       `IngestJob.set(wait: 15.minutes).perform_later(batch.id)` — and persist its `job.job_id`
       as the new `scheduled_job_id`.
     - **If discard raises `SolidQueue::Execution::UndiscardableError`** (job already claimed —
       i.e. a worker has picked it up and is about to call `perform`): do **not** enqueue a
       replacement job, and do not overwrite `scheduled_job_id`. The in-flight job will process
       whatever it finds in `batch_dir` when it reads it. This is the only intentionally accepted
       race in this design: the window is between a worker claiming the job and
       `ImagePreprocessor.process` reading the directory listing — essentially job-startup
       overhead, not the job's actual runtime — so an image landing in that window is rare and,
       if it happens, is silently dropped when `IngestJob`'s `ensure` block deletes `batch_dir`.
       Deliberately not solved here: handling it correctly would require either two jobs
       in flight for one batch (which then risks the second job reprocessing an already
       `completed` batch and clobbering its status, since `IngestJob#perform` has no idempotency
       guard) or a manifest/snapshot mechanism. Out of scope for this iteration; revisit if this
       proves to matter in practice.
   - Persist `next_image_index: index + 1` on the batch (always, regardless of the discard
     outcome above).
4. Respond `{ batch_id: batch.id, status: batch.status }` with `202 Accepted`. Note this is a
   contract change from current behavior: previously each request produced a new batch_id;
   now multiple requests within the debounce window share the same batch_id and `pending`
   status until the job actually fires.

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
