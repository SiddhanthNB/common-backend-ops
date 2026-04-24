# frozen_string_literal: true

require "concurrent"
require "ferrum"

require_relative "../common/app_logger"

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

    class BrowserAutomator
      def initialize(url:, browser_class: Ferrum::Browser, logger: AppLogger, sleeper: nil, monotonic_clock: nil, settings: {})
        @url = url
        @browser_class = browser_class
        @logger = logger
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @settings = settings
      end

      def call
        started_at = @monotonic_clock.call

        @logger.info("Starting keepalive for #{@url}")

        browser = @browser_class.new(
          timeout: 30,
          browser_options: {
            "ignore-certificate-errors" => nil,
            "no-sandbox" => nil
          }
        )

        page = browser.create_page
        page.headers.set("User-Agent" => USER_AGENT)
        page.set_viewport(width: 1280, height: 720)
        page.go_to(@url)

        response = page.network.response
        raise "No response received from the Streamlit app" if response.nil?

        status = response.status
        @logger.info("Initial response: [#{status}] #{response.status_text}")
        raise "Unexpected response status: #{status}" if status >= 400

        @logger.info("Waiting #{_setting(:page_load_grace_period_ms)}ms for the app to settle")
        _sleep_ms(_setting(:page_load_grace_period_ms))

        last_clicked_label = nil

        1.upto(_setting(:wake_max_attempts)) do |attempt|
          clicked = _find_and_click_wake_button(page)

          unless clicked
            elapsed_ms = _elapsed_ms(started_at)
            @logger.info(
              "Wake-up button not found after polling; assuming app is already awake " \
              "(attempt #{attempt}/#{_setting(:wake_max_attempts)})"
            )
            @logger.info("Keepalive succeeded in #{elapsed_ms}ms (already awake)")

            return {
              success: true,
              message: "Keepalive succeeded in #{elapsed_ms}ms (already awake)"
            }
          end

          last_clicked_label = clicked[:label]

          @logger.info(
            "Wake-up button clicked (#{clicked[:label]}) [attempt #{attempt}/#{_setting(:wake_max_attempts)}]; " \
            "waiting for app to become ready"
          )

          ready = _wait_for_app_ready(page, clicked[:context])
          raise "Wake-up button clicked but app did not become ready in time" unless ready

          _sleep_ms(2_000)

          button_still_there = _wake_button_present?(clicked[:context], tolerate_context_loss: true)
          unless button_still_there
            @logger.info("Wake-up button disappeared; app should be awake")
            elapsed_ms = _elapsed_ms(started_at)

            return {
              success: true,
              message: "Keepalive succeeded in #{elapsed_ms}ms (wake-up button clicked on #{last_clicked_label})"
            }
          end

          if attempt < _setting(:wake_max_attempts)
            backoff_ms = _setting(:wake_retry_backoff_base_ms) * (2**(attempt - 1))
            @logger.warn(
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

      private

      def _find_and_click_wake_button(page)
        poll_deadline = _deadline_ms(_setting(:wake_button_poll_timeout_ms))

        loop do
          _contexts(page).each do |context|
            button = _wake_button_for(context[:ctx])
            next unless button

            @logger.info("Wake-up button detected (#{context[:label]}); attempting to click")
            button.scroll_into_view
            next unless _clickable?(button)

            _sleep_ms(250)
            button.click(delay: 0.15)
            return {
              label: context[:label],
              context: context[:ctx]
            }
          end

          break if _monotonic_ms >= poll_deadline

          _sleep_ms(_setting(:wake_button_poll_interval_ms))
        end

        nil
      end

      def _wait_for_app_ready(page, context)
        deadline = _deadline_ms(_setting(:wake_ready_timeout_ms))

        loop do
          return true unless _wake_button_present?(context, tolerate_context_loss: true)
          return true if _network_idle?(page)
          return false if _monotonic_ms >= deadline

          _sleep_ms(500)
        end
      end

      def _wake_button_for(context)
        context.at_css(WAKE_UP_BUTTON_SELECTOR)
      rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
        nil
      rescue Ferrum::BrowserError => error
        return nil if _transient_context_error?(error)

        raise
      end

      def _wake_button_present?(context, tolerate_context_loss: false)
        !context.at_css(WAKE_UP_BUTTON_SELECTOR).nil?
      rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
        return false if tolerate_context_loss

        raise
      rescue Ferrum::BrowserError => error
        return false if tolerate_context_loss && _transient_context_error?(error)

        raise
      end

      def _clickable?(button)
        return true if button.in_viewport?

        button.find_position
        true
      rescue Ferrum::CoordinatesNotFoundError, Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
        false
      rescue Ferrum::BrowserError => error
        return false if _transient_context_error?(error)

        raise
      end

      def _network_idle?(page)
        page.network.wait_for_idle(connections: 2, duration: 0.25, timeout: 0.25)
      rescue Ferrum::TimeoutError
        false
      end

      def _contexts(page)
        contexts = [{ ctx: page, label: "main page" }]

        page.frames.reject(&:main?).each do |frame|
          contexts << { ctx: frame, label: "frame #{_frame_url(frame)}" }
        end

        contexts
      end

      def _frame_url(frame)
        frame.url
      rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
        "[no URL]"
      rescue Ferrum::BrowserError => error
        return "[no URL]" if _transient_context_error?(error)

        raise
      end

      def _transient_context_error?(error)
        message = error.message.to_s

        message.include?("There's no context available") ||
          message.include?("Cannot find context") ||
          message.include?("Execution context was destroyed")
      end

      def _sleep_ms(duration_ms)
        @sleeper.call(duration_ms / 1000.0)
      end

      def _elapsed_ms(started_at)
        ((@monotonic_clock.call - started_at) * 1000).round
      end

      def _deadline_ms(duration_ms)
        _monotonic_ms + duration_ms
      end

      def _monotonic_ms
        (@monotonic_clock.call * 1000).to_i
      end

      def _setting(name)
        @settings.fetch(name, Streamlit.const_get(name.to_s.upcase))
      end
    end

    class Orchestrator
      def initialize(urls:, concurrency:, automator_factory: nil, logger: AppLogger)
        @urls = urls
        @concurrency = concurrency
        @automator_factory = automator_factory || ->(url) { BrowserAutomator.new(url: url, logger: logger) }
        @logger = logger
      end

      def call
        executor = Concurrent::FixedThreadPool.new([@concurrency, @urls.size].min)
        mutex = Mutex.new
        results = []

        @urls.each do |url|
          executor.post do
            result = begin
              @automator_factory.call(url).call.merge(url: url)
            rescue StandardError => error
              @logger.error("Streamlit keepalive failed for #{url}: #{error.message}")
              {
                url: url,
                success: false,
                message: error.message
              }
            end

            mutex.synchronize { results << result }
          end
        end

        executor.shutdown
        finished = executor.wait_for_termination(600)
        raise "Timed out waiting for Streamlit keepalive workers to finish" unless finished

        results.sort_by! { |result| result[:url] }

        passed = results.count { |result| result[:success] }
        failed = results.count - passed

        {
          results: results,
          total: results.size,
          passed: passed,
          failed: failed
        }
      end
    end
  end
end
