# frozen_string_literal: true

module En57
  module Benchmark
    class AppendNonConflictingTags < Scenario
      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call(measure)
        type = "event_benchmarked"
        tags = %W[writer:#{SecureRandom.hex(4)}]
        scope = @event_store.read.of_type(type).with_tag(tags)
        events =
          Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

        measure.call do
          begin
            @event_store.append(events, fail_if: scope.after(position = 0))
          rescue AppendConditionViolated
            record_retry
            retry
          end
        end
        verify
      end

      def verify = @event_store.read.each.to_a.size == total_runs * @batch_size
    end
  end
end
