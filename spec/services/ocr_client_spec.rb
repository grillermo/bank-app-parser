require "rails_helper"

RSpec.describe OcrClient do
  let(:img) { Rails.root.join("tmp/ocr_test.png") }
  before do
    FileUtils.mkdir_p(Rails.root.join("tmp"))
    File.binwrite(img, "imgbytes")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
    allow(ENV).to receive(:[]).with("OPENAI_MODEL").and_return("gpt-5.4-nano-2026-03-17")
  end
  after { FileUtils.rm_f(img) }

  it "parses the JSON array from the model response" do
    content = '[{"date":"2025-10-12","description":"COFFEE","bank_name":"unknown","merchant":"Starbucks","cardname":"unknown","amount":-4.5,"category":"Food"}]'
    body = { "choices" => [{ "message" => { "content" => content } }] }.to_json
    fake_resp = double(status: double(success?: true), to_s: body)
    fake_http = double
    allow(HTTP).to receive(:auth).with("Bearer sk-test").and_return(fake_http)
    allow(fake_http).to receive(:post).and_return(fake_resp)

    result = OcrClient.extract(image_path: img)
    expect(result.first["merchant"]).to eq("Starbucks")
    expect(result.first["amount"]).to eq(-4.5)
  end

  it "strips markdown fences before parsing" do
    content = "```json\n[{\"date\":\"2025-10-12\",\"description\":\"X\",\"amount\":-1.0}]\n```"
    body = { "choices" => [{ "message" => { "content" => content } }] }.to_json
    fake_resp = double(status: double(success?: true), to_s: body)
    fake_http = double
    allow(HTTP).to receive(:auth).and_return(fake_http)
    allow(fake_http).to receive(:post).and_return(fake_resp)
    expect(OcrClient.extract(image_path: img).first["description"]).to eq("X")
  end

  it "raises on HTTP failure" do
    fake_resp = double(status: double(success?: false), to_s: "err")
    fake_http = double
    allow(HTTP).to receive(:auth).and_return(fake_http)
    allow(fake_http).to receive(:post).and_return(fake_resp)
    expect { OcrClient.extract(image_path: img) }.to raise_error(RuntimeError, /OCR request failed/)
  end
end
