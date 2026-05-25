# frozen_string_literal: true

require "pg"

module En57
  class PgAdapter
    def self.for_pool(connection_pool) = new(connection_pool)

    def self.for_connection(connection) = new(Mono.new(connection))

    def initialize(connection_pool)
      @connection_pool = connection_pool
    end

    def with_connection(&block) = @connection_pool.with(&block)

    def with_transaction(&block) = run_transaction("BEGIN", &block)

    def with_serializable_transaction(&block) =
      run_transaction("BEGIN ISOLATION LEVEL SERIALIZABLE", &block)

    def serialization_error = PG::TRSerializationFailure

    private

    def run_transaction(begin_statement)
      with_connection do |connection|
        connection.exec(begin_statement)
        result =
          begin
            yield connection
          rescue StandardError
            connection.exec("ROLLBACK")
            raise
          end
        connection.exec("COMMIT")
        result
      end
    end

    class Mono
      def initialize(connection)
        @connection = connection
        @mutex = Mutex.new
      end

      def with
        @mutex.synchronize { yield @connection }
      end
    end
  end

  class EventStore
    def self.for_pg(connection_uri)
      new(Repository.new(PgAdapter.for_connection(PG.connect(connection_uri))))
    end
  end

  if defined?(ConnectionPool)
    class EventStore
      def self.for_pooled_pg(connection_uri, max_connections: 5)
        new(
          Repository.new(
            PgAdapter.for_pool(
              ConnectionPool.new(size: max_connections) do
                PG.connect(connection_uri)
              end,
            ),
          ),
        )
      end
    end
  end
end
