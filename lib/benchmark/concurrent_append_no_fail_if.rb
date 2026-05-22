# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "concurrent-append-no-fail-if",
      name: "10x100 concurrent append, no fail_if",
      concurrency: 10,
      batch_size: 100,
    ) do
      def setup(database_url)
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      def call(measure, _retries, _run_id)
        concurrently do |writer_id, barrier|
          events =
            @batch_size.times.map do
              Event.new(
                type: "event_benchmarked",
                tags: ["writer:#{writer_id}"],
              )
            end
          barrier.wait

          measure.call { @event_store.append(events) }
        end
      end
    end
  end
end
