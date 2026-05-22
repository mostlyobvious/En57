# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define do
      database_instance "concurrent-append-no-fail-if"
      name "10x100 concurrent append, no fail_if"
      concurrency 10
      batch_size 100

      setup do |database_url|
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      call do |measure, _run_id|
        type = "event_benchmarked"
        concurrently do |writer_id, barrier|
          tags = %W[writer:#{writer_id}]
          events = Array.new(@batch_size) { Event.new(type: type, tags: tags) }

          barrier.wait

          measure.call { @event_store.append(events) }
        end
      end
    end
  end
end
