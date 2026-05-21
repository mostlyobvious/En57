# frozen_string_literal: true

module En57
  module Benchmark
    class AppendNoFailIf < Scenario
      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call
        type = "event_benchmarked"
        tags = %W[writer:#{SecureRandom.hex(4)}]
        events =
          Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

        @measure.call { @event_store.append(events) }
      end

      def verify = @event_store.read.each.to_a.size == total_runs * @batch_size
    end
  end
end
