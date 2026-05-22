# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define do
      database_instance "concurrent-append-conflicting-tags"
      name "10x100 concurrent append, conflicting tags"
      concurrency 10
      batch_size 100

      setup do |database_url|
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      call do |measure, run_id|
        type = "event_benchmarked"
        tags = %W[writer:#{run_id}]
        concurrently do |_writer_id, barrier|
          scope = @event_store.read.of_type(type).with_tag(tags)
          events = Array.new(@batch_size) { Event.new(type: type, tags: tags) }
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
      end
    end
  end
end
