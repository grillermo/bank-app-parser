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
