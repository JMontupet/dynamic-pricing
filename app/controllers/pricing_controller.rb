class PricingController < ApplicationController
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  before_action :validate_params

  def index
    rate = pricing_service.get_rate(
      period: params[:period],
      hotel:  params[:hotel],
      room:   params[:room]
    )
    render json: { rate: rate }
  rescue PricingModelClient::TransportError
    render json: { error: "Pricing service unavailable" }, status: :service_unavailable
  rescue PricingModelClient::ModelError => e
    render json: { error: e.message }, status: :bad_gateway
  rescue PricingModelClient::FormatError
    render json: { error: "Invalid pricing data" }, status: :bad_gateway
  rescue PricingModelClient::RateLimitError => e
    render json: { error: e.message }, status: :too_many_requests
  rescue PricingService::CircuitOpenError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def validate_params
    # Validate required parameters
    unless params[:period].present? && params[:hotel].present? && params[:room].present?
      return render json: { error: "Missing required parameters: period, hotel, room" }, status: :bad_request
    end

    # Validate parameter values
    unless VALID_PERIODS.include?(params[:period])
      return render json: { error: "Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}" }, status: :bad_request
    end

    unless VALID_HOTELS.include?(params[:hotel])
      return render json: { error: "Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}" }, status: :bad_request
    end

    unless VALID_ROOMS.include?(params[:room])
      return render json: { error: "Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}" }, status: :bad_request
    end
  end

  def pricing_service
    PricingService.instance
  end
end
