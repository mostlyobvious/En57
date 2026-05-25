# frozen_string_literal: true

require_relative "en57/version"
require_relative "en57/event"
require_relative "en57/json_serializer"
require_relative "en57/query"
require_relative "en57/scope"
require_relative "en57/pg_adapter"
require_relative "en57/sequel_adapter" if defined?(Sequel)
require_relative "en57/active_record_adapter" if defined?(ActiveRecord)
require_relative "en57/repository"
require_relative "en57/migrator"
require_relative "en57/event_store"
require_relative "en57/configuration"

module En57
  Success = Data.define
  Failure = Data.define
  SerializationError = Class.new(StandardError)

  def self.configuration = Configuration.instance

  def self.configure
    yield configuration
  ensure
    configuration.freeze
  end
end
