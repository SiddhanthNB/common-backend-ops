# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/healthcheck/redis"

class RedisHealthcheckTest < Minitest::Test
  class FakeClient
    attr_reader :closed, :uri

    def initialize(uri)
      @uri = uri
      @closed = false
    end

    def ping
      "PONG"
    end

    def close
      @closed = true
    end
  end

  def test_call_connects_with_encoded_uri_and_pings_redis
    captured_client = nil

    with_env(
      "REDIS_URL" => "redis://default:[YOUR-PASSWORD]@redis.example.com:6379",
      "REDIS_PASSWORD" => "pa$$ word"
    ) do
      Redis.stub(:new, lambda { |options|
        captured_client = FakeClient.new(options[:url])
      }) do
        result = Healthcheck::Redis.call

        assert_equal true, result[:success]
        assert_equal "Pinged Redis successfully!", result[:message]
        assert_equal "redis://default:pa%24%24+word@redis.example.com:6379", captured_client.uri
        assert_equal true, captured_client.closed
      end
    end
  end
end
