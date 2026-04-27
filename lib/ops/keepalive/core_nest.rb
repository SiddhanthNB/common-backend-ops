# frozen_string_literal: true

require "httpx"

module Keepalive
  module CoreNest
    def self.call(url:, timeout_milliseconds: 90_000)
      timeout = _timeout_seconds(timeout_milliseconds)
      response = HTTPX
        .with(timeout: { connect_timeout: timeout, write_timeout: timeout, operation_timeout: timeout })
        .get(url)

      {
        success: response.status >= 200 && response.status < 300,
        message: "Received HTTP #{response.status} from #{url}"
      }
    end

    def self._timeout_seconds(timeout_milliseconds)
      timeout_milliseconds.to_f / 1000
    end
  end
end
