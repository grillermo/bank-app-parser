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
