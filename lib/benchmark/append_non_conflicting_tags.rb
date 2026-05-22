# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define do
      database_instance "append-non-conflicting-tags"
      name "1x100 append, non-conflicting tags"
      runs { it * 10 }
      concurrency 1
      batch_size 100

      setup do |database_url|
        @event_store =
          EventStore.for_pooled_pg(database_url, max_connections: @concurrency)
      end

      call do |measure|
        type = "event_benchmarked"
        tags = %W[writer:#{SecureRandom.hex(4)}]
        scope = @event_store.read.of_type(type).with_tag(tags)
        events = Array.new(@batch_size) { Event.new(type: type, tags: tags) }

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
