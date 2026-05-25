# frozen_string_literal: true

require "pg"
require "sequel"

module En57
  class SequelAdapter
    def initialize(database)
      @database = database
    end

    def with_connection(&block)
      @database.synchronize(&block)
    end

    def with_transaction(&block) = run_transaction({}, &block)

    def with_serializable_transaction(&block) =
      run_transaction({ isolation: :serializable }, &block)

    def serialization_error = PG::TRSerializationFailure

    private

    def run_transaction(options)
      @database.transaction(**options) do
        @database.synchronize { |connection| yield connection }
      end
    rescue Sequel::DatabaseError => e
      raise e.wrapped_exception
    end
  end

  class EventStore
    def self.for_sequel(database)
      new(Repository.new(SequelAdapter.new(database)))
    end
  end
end
