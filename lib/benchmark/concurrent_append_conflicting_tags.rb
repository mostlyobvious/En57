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
        concurrently do |_writer_id, barrier|
          scope =
            @event_store
              .read
              .of_type(type = "event_benchmarked")
              .with_tag(tags = ["writer:#{run_id}"])
          events = @batch_size.times.map { Event.new(type:, tags:) }
          barrier.wait

          measure.call do
            begin
              @event_store.append(events, fail_if: scope.after(position = 0))
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
