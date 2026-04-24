# frozen_string_literal: true

require "http"

module Keepalive
  module CoreNest
    def self.call(url:, timeout_milliseconds: 90_000)
      timeout = _timeout_seconds(timeout_milliseconds)
      response = HTTP
        .timeout(connect: timeout, write: timeout, read: timeout)
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
