# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/keepalive/core_nest"

class CoreNestKeepaliveTest < Minitest::Test
  Status = Struct.new(:code) do
    def success?
      code >= 200 && code < 300
    end

    def to_s
      code.to_s
    end
  end

  Response = Struct.new(:status)

  def test_call_uses_timeout_and_returns_success_result
    captures = {}

    http_client = Object.new
    http_client.define_singleton_method(:headers) do |value|
      captures[:headers] = value
      self
    end
    http_client.define_singleton_method(:get) do |url|
      captures[:url] = url
      Response.new(Status.new(200))
    end

    HTTP.stub(:timeout, lambda { |options|
      captures[:timeout] = options
      http_client
    }) do
      result = Keepalive::CoreNest.call(url: "https://example.com/ping", timeout_milliseconds: 1500)

      assert_equal({ connect: 1.5, write: 1.5, read: 1.5 }, captures[:timeout])
      assert_equal({}, captures[:headers])
      assert_equal "https://example.com/ping", captures[:url]
      assert_equal true, result[:success]
      assert_equal "Received HTTP 200 from https://example.com/ping", result[:message]
    end
  end
end
