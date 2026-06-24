class OcrClient
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  PROMPT = <<~TXT.freeze
    You are an expert data extraction assistant. Your task is to analyze the provided screenshot of bank transactions and extract all line items into a clean, structured format.

    ### Instructions:
    1. Extract every unique transaction visible in the image.
    2. De-duplicate: The image may show the same transaction multiple times. Only record each unique transaction once.
    3. If a transaction is partially cut off at the very beginning or end of image video and the details are illegible, omit it.
    4. Convert all shorthand month names to standard full dates if the year is known (e.g., "Oct 12" -> "2025-10-12"). If the year is not visible, default to the current year 2026.

    ### Output Format:
    Provide the output strictly as a valid JSON array of objects (which I will convert to CSV). Do not include any conversational text, markdown formatting blocks (like ```json), or explanations.
    - "date": YYYY-MM-DD format
    - "description": The text description or vendor name
    - "bank_name": infer the name of the bank from the UI, if not sure output 'unknown'
    - "merchant": the name of the merchant if available otherwise 'unknown'
    - "cardname": infer the name of the credit card from the UI, if not sure output 'unknown'
    - "amount": The amount as a float (negative for expenditures/debits, positive for income/credits)
    - "category": A best-guess category based on the vendor name (e.g., Food, Utilities, Transport, Shopping)
    - "status": one of "pending", "posted", "canceled". Use "canceled" if the row is shown as canceled, reversed, voided, or refunded. Use "posted" if it is clearly cleared, charged, or settled. Use "pending" if it is shown as processing/pending OR if the status is ambiguous or unreadable (this is the default).
  TXT

  def self.extract(image_path:)
    model = ENV["OPENAI_MODEL"]
    raise "OPENAI_MODEL is not set" if model.to_s.strip.empty?

    b64 = Base64.strict_encode64(File.binread(image_path))
    payload = {
      model: model,
      messages: [{
        role: "user",
        content: [
          { type: "text", text: PROMPT },
          { type: "image_url", image_url: { url: "data:image/png;base64,#{b64}" } }
        ]
      }]
    }
    Rails.logger.debug("[OCR] posting #{image_path} to OpenAI model #{model}")
    resp = HTTP.auth("Bearer #{ENV['OPENAI_API_KEY']}").post(ENDPOINT, json: payload)
    raise "OCR request failed: #{resp.to_s}" unless resp.status.success?

    content = JSON.parse(resp.to_s).dig("choices", 0, "message", "content").to_s
    cleaned = content.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "").strip
    parsed = JSON.parse(cleaned)
    raise "OCR returned non-array" unless parsed.is_a?(Array)
    parsed
  end
end
