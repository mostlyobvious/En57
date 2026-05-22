# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "append-non-conflicting-tags",
      name: "1x100 append, non-conflicting tags",
      runs: ->(runs) { runs * 10 },
      concurrency: 1,
      batch_size: 100,
    ) do
      def setup(database_url)
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      def call(measure, run_id)
        scope =
          @event_store
            .read
            .of_type(type = "event_benchmarked")
            .with_tag(tags = ["writer:#{run_id}"])
        events = @batch_size.times.map { Event.new(type:, tags:) }

        measure.call do
          begin
            @event_store.append(events, fail_if: scope.after(position = 0))
          rescue AppendConditionViolated
            record_retry
            retry
          end
        end
      end
    end
  end
end
