# Client responsible for interacting with the external pricing model.
#
# Responsibilities:
# - Transport-level retries and timeouts
# - Validation of the model response contract
# 
class PricingModelClient
  MODEL_URL       = ENV.fetch("PRICING_MODEL_URL", "http://127.0.0.1:8080")
  TOKEN           = ENV.fetch("PRICING_MODEL_TOKEN")
  TIMEOUT_SECONDS = ENV.fetch("PRICING_MODEL_TIMEOUT", 1).to_f


  class Error < StandardError; end
  class TransportError < Error; end
  class ModelError < Error; end
  class FormatError < Error; end
  class RateLimitError < Error; end

  def initialize
    @conn = Faraday.new(url: MODEL_URL) do |f|
      f.headers["token"] = TOKEN
      f.request :json
      f.response :json, content_type: /\bjson\b/

      f.request :retry,
        max: 3,
        interval: 0.05,
        interval_randomness: 0.5,
        backoff_factor: 2,
        retry_statuses: [ 500, 502, 503, 504 ],
        methods: [ :post ]

      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS

      f.adapter Faraday.default_adapter
    end
  end

  def fetch_rates(attributes)
    response = @conn.post("/pricing") do |req|
      req.body = { attributes: attributes }
    end

    unless response.success?
      if response.status == 429
        raise RateLimitError, "Pricing model rate limit exceeded"
      end
      raise ModelError, "Model API HTTP #{response.status}"
    end

    body = response.body
    validate_response!(body)

    rates = body["rates"]
    # Rates may be returned as strings. Normalize to Integer for internal consistency.
    rates.each { |r| normalize_rate!(r) }
    rates
  rescue Faraday::Error, Timeout::Error => e
    raise TransportError, e.message
  end

  def fetch_rate(period:, hotel:, room:)
    rates = fetch_rates([{ period: period, hotel: hotel, room: room }])
    rate = rates.first
    raise FormatError, "Empty rates array" unless rate
    rate["rate"]
  end

  def validate_response!(body)
    unless body.is_a?(Hash)
      raise FormatError, "Response body is not a JSON object"
    end

    # The pricing model may return HTTP 200 with a business-level error payload.
    if body["status"] == "error"
      raise ModelError, body["message"] || "Pricing model error"
    end

    rates = body["rates"]
    unless rates.is_a?(Array)
      raise FormatError, "Missing rates"
    end

    rates.each do |r|
      raise FormatError, "Rate entry is not an object" unless r.is_a?(Hash)
      ["period", "hotel", "room", "rate"].each do |key|
        unless r.key?(key)
          raise FormatError, "Missing #{key}"
        end
      end
    end
  end


  def normalize_rate!(r)
    raw = r["rate"]
    case raw
    when String
      raise FormatError, "Empty rate" if raw.strip.empty?
      r["rate"] = raw
    when Integer
      r["rate"] = raw.to_s
    else
      raise FormatError, "Invalid rate type: #{raw.class}"
    end
  end
end