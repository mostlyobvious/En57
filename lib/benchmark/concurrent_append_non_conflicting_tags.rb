# frozen_string_literal: true

module En57
  module Benchmark
    class ConcurrentAppendNonConflictingTags < Scenario
      def self.key = "concurrent-append-non-conflicting-tags"

      def self.build(database_url:, warmup_runs:, runs:)
        new(
          name: "10x100 concurrent append, non-conflicting tags",
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
          scope = @event_store.read.of_type(type).with_tag(tags)
          events =
            Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

          barrier.wait

          measure.call do
            begin
              @event_store.append(events, fail_if: scope.after(position = 0))
            rescue AppendConditionViolated
              record_retry
              retry
            end
          end
        end
        verify
      end

      def verify =
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
    end
  end
end
