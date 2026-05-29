# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "append-no-fail-if-ar",
      name: "1x100 append, no fail_if (AR)",
      runs: ->(runs) { runs * 10 },
      concurrency: 1,
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

      def call(measure, _retries, run_id)
        events =
          @batch_size.times.map do
            Event.new(type: "event_benchmarked", tags: ["writer:#{run_id}"])
          end

        measure.call { @event_store.append(events) }
      end
    end
  end
end
