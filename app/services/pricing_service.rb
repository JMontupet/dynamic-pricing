# Fetches hotel room rates from the PricingModelClient.
# 
#   - In-memory caching with CACHE_TTL and SOFT_TTL (async refresh for stale data)
#   - Circuit breaker to prevent repeated failing calls to the pricing model
#   - Async background refresh when soft TTL is exceeded, returning cached value immediately
#   
class PricingService
  include Singleton

  # Main cache TTL and "soft" TTL for async refresh
  CACHE_TTL = 300
  SOFT_TTL  = 240

  # Circuit breaker configuration
  CB_THRESHOLD      = 5
  CB_RESET_TIMEOUT  = 10

  class CircuitOpenError < PricingModelClient::Error; end

  def initialize(
    cache: Rails.cache,
    client: PricingModelClient.new
  )
    @cache  = cache
    @client = client

    @cb_mutex     = Mutex.new
    @cb_failures  = 0
    @cb_opened_at = nil
  end

  # Returns the rate for a given period/hotel/room
  def get_rate(period:, hotel:, room:)
    key = cache_key(period, hotel, room)

    # Cache read
    cached_entry = @cache.read(key)
    if cached_entry
      age = Time.now - cached_entry[:fetched_at]
      if age <= SOFT_TTL
        return cached_entry[:rate]
      else
        refresh_cache_async(period, hotel, room)
        return cached_entry[:rate]
      end
    end

    # Call pricing model
    fetch_and_cache(period, hotel, room)
  end

  private

  def fetch_and_cache(period, hotel, room)
    @cb_mutex.synchronize { raise_circuit_if_open }

    rate = @client.fetch_rate(period: period, hotel: hotel,room: room)
    key = cache_key(period, hotel, room)
    @cache.write(key, { 
        rate: rate,
        fetched_at: Time.now
    }, expires_in: CACHE_TTL)

    # Reset circuit breaker
    @cb_mutex.synchronize do
      @cb_failures = 0
      @cb_opened_at = nil
    end

    rate
  rescue PricingModelClient::Error => e
    # Increment failure count
    @cb_mutex.synchronize do
      @cb_failures += 1
      @cb_opened_at ||= Time.now if @cb_failures >= CB_THRESHOLD
    end
    raise e
  end

  def refresh_cache_async(period, hotel, room)
    Thread.new do
      begin
        fetch_and_cache(period, hotel, room)
      rescue PricingModelClient::Error => e
        Rails.logger.warn("[PricingService] Async refresh failed: #{e.message}")
      end
    end
  end

  def cache_key(period, hotel, room)
    "pricing:#{period}:#{hotel}:#{room}"
  end

  def raise_circuit_if_open
    return unless @cb_opened_at

    if Time.now - @cb_opened_at > CB_RESET_TIMEOUT
      # Try to close circuit
      @cb_failures = 0
      @cb_opened_at = nil
    else
      raise CircuitOpenError, "Circuit open: too many failures"
    end
  end
end