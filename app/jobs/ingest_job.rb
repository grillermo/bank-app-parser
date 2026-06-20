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
