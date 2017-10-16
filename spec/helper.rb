require "bundler/setup"

if ENV["REPORT_COVERAGE"]
  require "coveralls"
  Coveralls.wear_merged!
  SimpleCov.merge_timeout(3600)
  SimpleCov.command_name("spec:functional")
end

require "fileutils"
require "neovim"
require "pry"
require "rubygems"
require "stringio"
require "timeout"
require "securerandom"
require "msgpack"

require File.expand_path("../support.rb", __FILE__)

RSpec.configure do |config|
  config.expect_with :rspec do |exp|
    exp.syntax = :expect
  end

  config.disable_monkey_patching!
  config.order = :random
  config.color = true
  config.filter_run_excluding :embedded

  config.around(:example) do |spec|
    Support.setup_workspace
    timeout = spec.metadata.fetch(:timeout, 3)

    begin
      Timeout.timeout(timeout) { spec.run }
    ensure
      Support.teardown_workspace
    end
  end

  config.around(:example, :silence_warnings) do |spec|
    old_logger = Neovim.logger
    log_target = StringIO.new
    Neovim.logger = Logger.new(log_target)
    Neovim.logger.level = Logger::WARN

    begin
      spec.run

      expect(log_target.string).not_to be_empty,
        ":silence_warnings used but nothing logged at WARN level"
    ensure
      Neovim.logger = old_logger
    end
  end

  Kernel.srand config.seed
end

Thread.abort_on_exception = true
