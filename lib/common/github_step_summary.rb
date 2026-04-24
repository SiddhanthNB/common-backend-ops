# frozen_string_literal: true

module GithubStepSummary
  def self.append(markdown)
    path = ENV["GITHUB_STEP_SUMMARY"]
    return if path.nil? || path.empty?

    File.open(path, "a") do |file|
      file.puts(markdown)
      file.puts
    end
  end
end
