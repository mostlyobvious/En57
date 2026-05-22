# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "res-append-stream-any",
      name: "1x100 append, expected_version :any (RES)",
      runs: ->(runs) { runs * 10 },
      concurrency: 1,
      batch_size: 100,
    ) do
      def setup(database_url)
        require "active_record"
        require "rails_event_store"

        ActiveRecord::Base.establish_connection(database_url)
        @event_store = RailsEventStore::JSONClient.new
      end

      def call(measure, run_id)
        events =
          @batch_size.times.map do
            RubyEventStore::Event.new(
              metadata: {
                event_type: "event_benchmarked",
              },
            )
          end

        measure.call do
          @event_store.append(
            events,
            stream_name: "writer:#{run_id}",
            expected_version: :any,
          )
        end
      end
    end
  end
end
