# frozen_string_literal: true

require "http"

module Keepalive
  module CoreNest
    def self.call(url:, timeout_milliseconds: 90_000)
      response = HTTP
        .timeout(
          connect: _timeout_seconds(timeout_milliseconds),
          write: _timeout_seconds(timeout_milliseconds),
          read: _timeout_seconds(timeout_milliseconds)
        )
        .headers({})
        .get(url)

      {
        success: response.status.success?,
        message: "Received HTTP #{response.status} from #{url}"
      }
    end

    def self._timeout_seconds(timeout_milliseconds)
      timeout_milliseconds.to_f / 1000
    end
  end
end
