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
