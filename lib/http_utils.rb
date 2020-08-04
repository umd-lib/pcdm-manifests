# frozen_string_literal: true

require 'errors'
require 'faraday'
require 'faraday_middleware'

# Useful HTTP methods
module HttpUtils
  include Errors

  HTTP_CONN = Faraday.new(ssl: { verify: false }, request: { params_encoder: Faraday::FlatParamsEncoder }) do |faraday|
    faraday.response :json, content_type: /\bjson$/
    faraday.adapter Faraday.default_adapter
  end

  def http_get(url, params = {})
    begin
      response = HTTP_CONN.get url, params
    rescue Faraday::ConnectionFailed => e
      raise InternalServerError, "Unable to connect to <#{url}> with error: #{e.message}"
    end
    raise InternalServerError, "Got a #{response.status} response from #{url}" unless response.success?

    response
  end
end
