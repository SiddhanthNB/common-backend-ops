# frozen_string_literal: true

require "logger"
require "time"

module AppLogger
  def self._logger
    @logger ||= begin
      instance = Logger.new($stdout)
      instance.level = _level
      instance.formatter = proc do |severity, datetime, _progname, message|
        "#{datetime.utc.iso8601} #{severity} #{message}\n"
      end
      instance
    end
  end

  def self.debug(message)
    _logger.debug(message)
  end

  def self.info(message)
    _logger.info(message)
  end

  def self.warn(message)
    _logger.warn(message)
  end

  def self.error(message)
    _logger.error(message)
  end

  def self._level
    Logger.const_get(ENV.fetch("LOG_LEVEL", "INFO").upcase)
  rescue NameError
    Logger::INFO
  end
end
