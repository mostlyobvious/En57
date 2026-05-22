# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define do
      database_instance "concurrent-append-no-fail-if"
      name "10x100 concurrent append, no fail_if"
      concurrency 10
      batch_size 100

      setup do
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      call do |measure|
        type = "event_benchmarked"
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          tags = %W[writer:#{SecureRandom.hex(4)}]
          events = Array.new(@batch_size) { Event.new(type: type, tags: tags) }

          barrier.wait

          measure.call { @event_store.append(events) }
        end
      end

      verify do
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
      end
    end
  end
end
