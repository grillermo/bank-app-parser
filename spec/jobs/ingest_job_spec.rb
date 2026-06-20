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
