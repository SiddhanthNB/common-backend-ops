# frozen_string_literal: true

require "ferrum"

require_relative "../common/app_logger"
require_relative "../common/env_vars"

module Keepalive
  module Streamlit
    PAGE_LOAD_GRACE_PERIOD_MS = 5_000
    WAKE_BUTTON_POLL_TIMEOUT_MS = 60_000
    WAKE_BUTTON_POLL_INTERVAL_MS = 1_000
    WAKE_MAX_ATTEMPTS = 3
    WAKE_RETRY_BACKOFF_BASE_MS = 2_000
    WAKE_READY_TIMEOUT_MS = 120_000
    WAKE_UP_BUTTON_SELECTOR = "[data-testid=\"wakeup-button-viewer\"]"
    USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

    def self.call(url: EnvVars.fetch("STREAMLIT_URL"))
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      AppLogger.info("Starting keepalive for #{url}")

      browser = Ferrum::Browser.new(
        timeout: 30,
        browser_options: {
          "ignore-certificate-errors" => nil,
          "no-sandbox" => nil
        }
      )

      page = browser.create_page
      page.headers.set("User-Agent" => USER_AGENT)
      page.set_viewport(width: 1280, height: 720)
      page.go_to(url)

      response = page.network.response
      raise "No response received from the Streamlit app" if response.nil?

      status = response.status
      AppLogger.info("Initial response: [#{status}] #{response.status_text}")
      raise "Unexpected response status: #{status}" if status >= 400

      AppLogger.info("Waiting #{PAGE_LOAD_GRACE_PERIOD_MS}ms for the app to settle")
      _sleep_ms(PAGE_LOAD_GRACE_PERIOD_MS)

      last_clicked_label = nil

      1.upto(WAKE_MAX_ATTEMPTS) do |attempt|
        clicked = _find_and_click_wake_button(page)

        unless clicked
          elapsed_ms = _elapsed_ms(started_at)
          AppLogger.info("Wake-up button not found after polling; assuming app is already awake (attempt #{attempt}/#{WAKE_MAX_ATTEMPTS})")
          AppLogger.info("Keepalive succeeded in #{elapsed_ms}ms (already awake)")

          return {
            success: true,
            message: "Keepalive succeeded in #{elapsed_ms}ms (already awake)"
          }
        end

        last_clicked_label = clicked[:label]

        AppLogger.info(
          "Wake-up button clicked (#{clicked[:label]}) [attempt #{attempt}/#{WAKE_MAX_ATTEMPTS}]; waiting for app to become ready"
        )

        ready = _wait_for_app_ready(page, clicked[:context])
        raise "Wake-up button clicked but app did not become ready in time" unless ready

        _sleep_ms(2_000)

        button_still_there = _wake_button_present?(clicked[:context], tolerate_context_loss: true)
        unless button_still_there
          AppLogger.info("Wake-up button disappeared; app should be awake")
          elapsed_ms = _elapsed_ms(started_at)

          return {
            success: true,
            message: "Keepalive succeeded in #{elapsed_ms}ms (wake-up button clicked on #{last_clicked_label})"
          }
        end

        if attempt < WAKE_MAX_ATTEMPTS
          backoff_ms = WAKE_RETRY_BACKOFF_BASE_MS * (2**(attempt - 1))
          AppLogger.warn(
            "Wake-up button still present after attempt #{attempt}; retrying in #{backoff_ms}ms"
          )
          _sleep_ms(backoff_ms)
        else
          raise "Wake-up button still present after all wake attempts; app may still be sleeping"
        end
      end
    ensure
      browser&.quit
    end

    def self._find_and_click_wake_button(page)
      poll_deadline = _deadline_ms(WAKE_BUTTON_POLL_TIMEOUT_MS)

      loop do
        _contexts(page).each do |context|
          button = _wake_button_for(context[:ctx])
          next unless button

          AppLogger.info("Wake-up button detected (#{context[:label]}); attempting to click")
          button.scroll_into_view
          next unless _clickable?(button)

          _sleep_ms(250)
          button.click(delay: 0.15)
          return context
        end

        break if _monotonic_ms >= poll_deadline

        _sleep_ms(WAKE_BUTTON_POLL_INTERVAL_MS)
      end

      nil
    end

    def self._wait_for_app_ready(page, context)
      deadline = _deadline_ms(WAKE_READY_TIMEOUT_MS)

      loop do
        return true unless _wake_button_present?(context, tolerate_context_loss: true)
        return true if _network_idle?(page)
        return false if _monotonic_ms >= deadline

        _sleep_ms(500)
      end
    end

    def self._wake_button_for(context)
      context.at_css(WAKE_UP_BUTTON_SELECTOR)
    rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
      nil
    rescue Ferrum::BrowserError => error
      return nil if _transient_context_error?(error)

      raise
    end

    def self._wake_button_present?(context, tolerate_context_loss: false)
      !context.at_css(WAKE_UP_BUTTON_SELECTOR).nil?
    rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
      return false if tolerate_context_loss

      raise
    rescue Ferrum::BrowserError => error
      return false if tolerate_context_loss && _transient_context_error?(error)

      raise
    end

    def self._clickable?(button)
      return true if button.in_viewport?

      button.find_position
      true
    rescue Ferrum::CoordinatesNotFoundError, Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
      false
    rescue Ferrum::BrowserError => error
      return false if _transient_context_error?(error)

      raise
    end

    def self._network_idle?(page)
      page.network.wait_for_idle(connections: 2, duration: 0.25, timeout: 0.25)
    rescue Ferrum::TimeoutError
      false
    end

    def self._contexts(page)
      contexts = [{ ctx: page, label: "main page" }]

      page.frames.reject(&:main?).each do |frame|
        contexts << { ctx: frame, label: "frame #{_frame_url(frame)}" }
      end

      contexts
    end

    def self._frame_url(frame)
      frame.url
    rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
      "[no URL]"
    rescue Ferrum::BrowserError => error
      return "[no URL]" if _transient_context_error?(error)

      raise
    end

    def self._transient_context_error?(error)
      message = error.message.to_s

      message.include?("There's no context available") ||
        message.include?("Cannot find context") ||
        message.include?("Execution context was destroyed")
    end

    def self._sleep_ms(duration_ms)
      sleep(duration_ms / 1000.0)
    end

    def self._elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def self._deadline_ms(duration_ms)
      _monotonic_ms + duration_ms
    end

    def self._monotonic_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
    end
  end
end
