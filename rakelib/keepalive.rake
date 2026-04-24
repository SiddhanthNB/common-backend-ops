require "yaml"
require "concurrent"

namespace :keepalive do
  desc "Ping the Core Nest keepalive endpoint"
  task :core_nest do
    require_relative "../lib/common/service_task_runner"
    require_relative "../lib/keepalive/core_nest"

    config_path = File.expand_path("../config/keepalive/core_nest.yaml", __dir__)
    config = YAML.safe_load(File.read(config_path), aliases: false) || {}
    url = config.fetch("url")
    timeout_milliseconds = Integer(config.fetch("timeout_milliseconds", 90_000))

    ServiceTaskRunner.run("Core Nest Keepalive") do
      Keepalive::CoreNest.call(url: url, timeout_milliseconds: timeout_milliseconds)
    end
  end

  desc "Wake Streamlit apps listed in config/keepalive/streamlit.yaml"
  task :streamlit do
    require_relative "../lib/common/app_logger"
    require_relative "../lib/common/github_step_summary"
    require_relative "../lib/common/service_task_runner"
    require_relative "../lib/keepalive/streamlit"

    config_path = File.expand_path("../config/keepalive/streamlit.yaml", __dir__)
    config = YAML.safe_load(File.read(config_path), aliases: false) || {}
    targets = config.fetch("targets", [])
    concurrency = Integer(config.fetch("concurrency", 2))

    raise "No Streamlit targets configured in #{config_path}" if targets.empty?
    raise "Invalid Streamlit concurrency: #{concurrency}" if concurrency <= 0

    ServiceTaskRunner.run("Streamlit Keepalive") do
      executor = Concurrent::FixedThreadPool.new([concurrency, targets.size].min)
      mutex = Mutex.new
      results = []

      targets.each do |url|
        executor.post do
          result = begin
            Keepalive::Streamlit.call(url: url).merge(url: url)
          rescue StandardError => error
            AppLogger.error("Streamlit keepalive failed for #{url}: #{error.message}")
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

      results.each do |result|
        GithubStepSummary.append(
          [
            "### #{result[:url]}",
            "",
            "- Status: #{result[:success] ? 'SUCCESS' : 'FAILURE'}",
            "- Details: #{result[:message]}"
          ].join("\n")
        )
      end

      {
        success: failed.zero?,
        message: "#{passed}/#{results.size} Streamlit targets passed"
      }
    end
  end
end
