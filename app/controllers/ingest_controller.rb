class IngestController < ActionController::API
  before_action :authenticate

  def self.batch_dir(batch_id)
    Rails.root.join("tmp/ingest", batch_id.to_s)
  end

  def create
    image = params[:image]
    return render(json: { error: "no image" }, status: :unprocessable_entity) if image.blank? || image.is_a?(Array)

    batch = Batch.open_for_ingest
    batch.append_image!(image)
    Rails.logger.debug("[Ingest] saved image #{batch.next_image_index} for batch #{batch.id} to #{self.class.batch_dir(batch.id)}")

    render json: { batch_id: batch.id, status: batch.status }, status: :accepted
  rescue Batch::FullBatchError
    render json: { error: "batch image limit reached" }, status: :unprocessable_entity
  end

  private

  def authenticate
    header = request.headers["Authorization"].to_s
    token = header.split(" ", 2).last
    puts "Token #{token} and env #{ENV["INGEST_TOKEN"]}"
    unless ActiveSupport::SecurityUtils.secure_compare(token.to_s, ENV["INGEST_TOKEN"].to_s)
      render json: { error: "unauthorized" }, status: :unauthorized
    end
  end
end
