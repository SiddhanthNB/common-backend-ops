require "yaml"

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
    require_relative "../lib/common/github_step_summary"
    require_relative "../lib/common/service_task_runner"
    require_relative "../lib/keepalive/streamlit"

    config_path = File.expand_path("../config/keepalive/streamlit.yaml", __dir__)
    config = YAML.safe_load(File.read(config_path), aliases: false) || {}
    targets = config.fetch("targets", [])
    concurrency = Integer(config.fetch("concurrency", 2))

    raise "No Streamlit targets configured in #{config_path}" if targets.empty?
    raise "Invalid Streamlit concurrency: #{concurrency}" if concurrency <= 0

    orchestrator = Keepalive::Streamlit::Orchestrator.new(urls: targets, concurrency: concurrency)

    ServiceTaskRunner.run("Streamlit Keepalive") do
      result = orchestrator.call

      result[:results].each do |target_result|
        GithubStepSummary.append(
          [
            "### #{target_result[:url]}",
            "",
            "- Status: #{target_result[:success] ? 'SUCCESS' : 'FAILURE'}",
            "- Details: #{target_result[:message]}"
          ].join("\n")
        )
      end

      {
        success: result[:failed].zero?,
        message: "#{result[:passed]}/#{result[:total]} Streamlit targets passed"
      }
    end
  end
end
