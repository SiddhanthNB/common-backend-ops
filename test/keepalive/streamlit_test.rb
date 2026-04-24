# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/keepalive/streamlit"

class StreamlitKeepaliveTest < Minitest::Test
  Response = Struct.new(:status, :status_text)

  class FakeHeaders
    attr_reader :value

    def set(value)
      @value = value
    end
  end

  class FakeNetwork
    attr_reader :response

    def initialize(response, idle_result: false)
      @response = response
      @idle_result = idle_result
    end

    def wait_for_idle(**)
      @idle_result
    end
  end

  class FakePage
    attr_reader :headers, :network, :goto_url, :viewport

    def initialize(response:, buttons:, frames: [], idle_result: false)
      @headers = FakeHeaders.new
      @network = FakeNetwork.new(response, idle_result: idle_result)
      @buttons = buttons.dup
      @frames = frames
    end

    def set_viewport(width:, height:)
      @viewport = [width, height]
    end

    def go_to(url)
      @goto_url = url
    end

    def frames
      @frames
    end

    def at_css(_selector)
      @buttons.shift
    end
  end

  class FakeButton
    attr_reader :clicked

    def scroll_into_view; end

    def in_viewport?
      true
    end

    def click(**)
      @clicked = true
    end
  end

  class FakeBrowser
    attr_reader :page, :quit_called

    def initialize(page)
      @page = page
      @quit_called = false
    end

    def create_page
      @page
    end

    def quit
      @quit_called = true
    end
  end

  def setup
    reset_app_logger!
  end

  def test_browser_automator_returns_success_when_app_is_already_awake
    page = FakePage.new(
      response: Response.new(200, "OK"),
      buttons: [nil]
    )
    browser = FakeBrowser.new(page)
    browser_class = Object.new
    browser_class.define_singleton_method(:new) { |_options| browser }

    runner = Keepalive::Streamlit::BrowserAutomator.new(
      url: "https://example.com",
      browser_class: browser_class,
      sleeper: ->(*) {},
      monotonic_clock: -> { 0.0 },
      settings: {
        page_load_grace_period_ms: 0,
        wake_button_poll_timeout_ms: 0
      }
    )

    result = runner.call

    assert_equal true, result[:success]
    assert_equal "Keepalive succeeded in 0ms (already awake)", result[:message]
    assert_equal "https://example.com", page.goto_url
    assert_equal [1280, 720], page.viewport
    assert_equal({ "User-Agent" => Keepalive::Streamlit::USER_AGENT }, page.headers.value)
    assert_equal true, browser.quit_called
  end

  def test_browser_automator_clicks_wake_button_and_reports_success
    button = FakeButton.new
    page = FakePage.new(
      response: Response.new(200, "OK"),
      buttons: [button, nil, nil]
    )
    browser = FakeBrowser.new(page)
    browser_class = Object.new
    browser_class.define_singleton_method(:new) { |_options| browser }

    runner = Keepalive::Streamlit::BrowserAutomator.new(
      url: "https://example.com",
      browser_class: browser_class,
      sleeper: ->(*) {},
      monotonic_clock: -> { 0.0 },
      settings: {
        page_load_grace_period_ms: 0,
        wake_button_poll_timeout_ms: 0,
        wake_ready_timeout_ms: 0
      }
    )

    result = runner.call

    assert_equal true, result[:success]
    assert_equal "Keepalive succeeded in 0ms (wake-up button clicked on main page)", result[:message]
    assert_equal true, button.clicked
    assert_equal true, browser.quit_called
  end

  def test_orchestrator_aggregates_successes_and_failures
    automator_factory = lambda do |url|
      target = Object.new
      target.define_singleton_method(:call) do
        raise "timeout" if url.include?("two")

        { success: true, message: "ok" }
      end
      target
    end

    result = Keepalive::Streamlit::Orchestrator.new(
      urls: ["https://two.example.com", "https://one.example.com"],
      concurrency: 2,
      automator_factory: automator_factory
    ).call

    assert_equal 2, result[:total]
    assert_equal 1, result[:passed]
    assert_equal 1, result[:failed]
    assert_equal(
      [
        { url: "https://one.example.com", success: true, message: "ok" },
        { url: "https://two.example.com", success: false, message: "timeout" }
      ],
      result[:results]
    )
  end
end
