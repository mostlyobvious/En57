# frozen_string_literal: true

require "pg"

module En57
  class ActiveRecordAdapter
    def initialize(connection_pool)
      @connection_pool = connection_pool
    end

    def with_connection
      @connection_pool.with_connection do |connection|
        yield connection.raw_connection
      end
    end

    def with_transaction(&block) = run_transaction({}, &block)

    def with_serializable_transaction(&block) =
      run_transaction({ isolation: :serializable }, &block)

    def serialization_error = ActiveRecord::SerializationFailure

    private

    def run_transaction(options)
      @connection_pool.with_connection do |connection|
        connection.transaction(**options) { yield connection.raw_connection }
      end
    end
  end

  class EventStore
    def self.for_active_record(model = ActiveRecord::Base)
      new(Repository.new(ActiveRecordAdapter.new(model.connection_pool)))
    end
  end
end
