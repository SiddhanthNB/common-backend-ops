# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/ops/keepalive/core_nest"

class CoreNestKeepaliveTest < Minitest::Test
  Response = Struct.new(:status)

  def test_call_uses_timeout_and_returns_success_result
    captures = {}

    http_client = Object.new
    http_client.define_singleton_method(:get) do |url|
      captures[:url] = url
      Response.new(200)
    end

    HTTPX.stub(:with, lambda { |options|
      captures[:timeout] = options[:timeout]
      http_client
    }) do
      result = Keepalive::CoreNest.call(url: "https://example.com/ping", timeout_milliseconds: 1500)

      assert_equal(
        { connect_timeout: 1.5, write_timeout: 1.5, operation_timeout: 1.5 },
        captures[:timeout]
      )
      assert_equal "https://example.com/ping", captures[:url]
      assert_equal true, result[:success]
      assert_equal "Received HTTP 200 from https://example.com/ping", result[:message]
    end
  end
end
