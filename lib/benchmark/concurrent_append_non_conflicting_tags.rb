# frozen_string_literal: true

module En57
  module Benchmark
    concurrent_append_non_conflicting_tags =
      Scenario.define(
        database_instance: "concurrent-append-non-conflicting-tags",
        name: "10x100 concurrent append, non-conflicting tags",
        concurrency: 10,
        batch_size: 100,
      ) do
        def setup(database_url)
          @event_store =
            EventStore.for_pooled_pg(
              database_url,
              max_connections: @concurrency,
            )
        end

        def call(measure, retries, _run_id)
          concurrently do |writer_id, barrier|
            scope =
              @event_store
                .read
                .of_type(type = "event_benchmarked")
                .with_tag(tags = ["writer:#{writer_id}"])
            events = @batch_size.times.map { Event.new(type:, tags:) }
            barrier.wait

            position = 0
            measure.call do
              loop do
                case @event_store.append(events, fail_if: scope.after(position))
                in Success
                  break
                in Failure(position:)
                  retries.call
                end
              end
            end
          end
        end
      end

    concurrent_append_non_conflicting_tags.with(
      database_instance: "concurrent-append-non-conflicting-tags-seeded",
      name: "10x100 concurrent append, non-conflicting tags (seeded)",
    )
  end
end
