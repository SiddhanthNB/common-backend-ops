# frozen_string_literal: true

require "httpx"
require_relative "../../common/env_vars"

module Healthcheck
  module Qdrant
    def self.call
      healthz_response = _http_client.get("#{_base_url}/healthz")
      healthz_response.json rescue {} if _successful_status?(healthz_response.status)

      collections_response = nil
      if _successful_status?(healthz_response.status)
        collections_response = _http_client.get("#{_base_url}/collections")
        collections_response.json rescue {}
      end

      success = _successful_status?(healthz_response.status) &&
                !collections_response.nil? &&
                _successful_status?(collections_response.status)

      {
        success: success,
        message: _message(healthz_response, collections_response)
      }
    end

    def self._http_client
      HTTPX.with(
        timeout: {
          connect_timeout: 5,
          write_timeout: 5,
          operation_timeout: 10
        },
        headers: {
          "api-key" => EnvVars.fetch("QDRANT_ACCESS_KEY")
        }
      )
    end

    def self._base_url
      EnvVars.fetch("QDRANT_URL").sub(%r{/\z}, "")
    end

    def self._successful_status?(status)
      status >= 200 && status < 300
    end

    def self._message(healthz_response, collections_response)
      if collections_response
        "Qdrant healthz=#{healthz_response.status}, collections=#{collections_response.status}"
      else
        "Qdrant healthz=#{healthz_response.status}"
      end
    end
  end
end
