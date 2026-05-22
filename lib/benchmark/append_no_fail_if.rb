# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define do
      database_instance "append-no-fail-if"
      name "1x100 append, no fail_if"
      runs { it * 10 }
      concurrency 1
      batch_size 100

      setup do |database_url|
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      call do |measure, run_id|
        events =
          @batch_size.times.map do
            Event.new(type: "event_benchmarked", tags: ["writer:#{run_id}"])
          end

        measure.call { @event_store.append(events) }
      end
    end
  end
end
