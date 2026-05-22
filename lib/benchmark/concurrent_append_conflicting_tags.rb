# frozen_string_literal: true

module En57
  module Benchmark
    class ConcurrentAppendConflictingTags < Scenario
      def self.key = "concurrent-append-conflicting-tags"

      def self.build(database_url:, warmup_runs:, runs:)
        new(
          name: "10x100 concurrent append, conflicting tags",
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
        tags = %W[writer:#{SecureRandom.hex(4)}]
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          scope = @event_store.read.of_type(type).with_tag(tags)
          events =
            Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }
          position = 0

          barrier.wait

          measure.call do
            begin
              @event_store.append(events, fail_if: scope.after(position))
            rescue AppendConditionViolated
              record_retry
              scope.each_with_position do |_event, event_position|
                position = event_position
              end
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
