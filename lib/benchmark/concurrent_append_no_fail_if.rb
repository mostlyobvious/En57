# frozen_string_literal: true

module En57
  module Benchmark
    class ConcurrentAppendNoFailIf < Scenario
      def self.key = "concurrent-append-no-fail-if"

      def self.build(database_url:, warmup_runs:, runs:)
        new(
          name: "10x100 concurrent append, no fail_if",
          database_url:,
          warmup_runs:,
          runs:,
          concurrency: 10,
          batch_size: 100,
        )
      end

      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call(measure)
        type = "event_benchmarked"
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          tags = %W[writer:#{SecureRandom.hex(4)}]
          events =
            Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

          barrier.wait

          measure.call { @event_store.append(events) }
        end
        verify
      end

      def verify =
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
    end
  end
end
