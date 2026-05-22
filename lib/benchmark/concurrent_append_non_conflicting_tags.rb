# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define do
      database_instance "concurrent-append-non-conflicting-tags"
      name "10x100 concurrent append, non-conflicting tags"
      concurrency 10
      batch_size 100

      setup do |database_url|
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      call do |measure|
        type = "event_benchmarked"
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          tags = %W[writer:#{SecureRandom.hex(4)}]
          scope = @event_store.read.of_type(type).with_tag(tags)
          events = Array.new(@batch_size) { Event.new(type: type, tags: tags) }

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
      end
    end
  end
end
