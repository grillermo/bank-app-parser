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
