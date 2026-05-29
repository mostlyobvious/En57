# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "concurrent-append-no-fail-if-ar",
      name: "10x100 concurrent append, no fail_if (AR)",
      concurrency: 10,
      batch_size: 100,
    ) do
      def setup(database_url)
        require "active_record"
        require_relative "../en57/active_record_adapter"

        ActiveRecord::Base.establish_connection(
          url: database_url,
          pool: @concurrency,
        )
        @event_store = EventStore.for_active_record
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
