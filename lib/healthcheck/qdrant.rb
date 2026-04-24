# frozen_string_literal: true

require "http"
require_relative "../common/env_vars"

module Healthcheck
  module Qdrant
    def self.call
      healthz_response = _http_client.get("#{_base_url}/healthz")
      healthz_response.parse rescue {} if healthz_response.status.success?

      if healthz_response.status.success?
        collections_response = _http_client.get("#{_base_url}/collections")
      end

      {
        success: collections_response.status.success?,
        message: "Pinged Qdrant successfully!"
      }
    end

    def self._http_client
      HTTP
        .timeout(connect: 5, read: 10, write: 5)
        .headers("api-key" => EnvVars.fetch("QDRANT_ACCESS_KEY"))
    end

    def self._base_url
      EnvVars.fetch("QDRANT_URL").sub(%r{/\z}, "")
    end
  end
end
