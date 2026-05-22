# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "res-concurrent-append-non-conflicting-streams",
      name: "10x100 concurrent append, non-conflicting streams (RES)",
      concurrency: 10,
      batch_size: 100,
    ) do
      def setup(database_url)
        require "active_record"
        require "rails_event_store"

        ActiveRecord::Base.establish_connection(database_url)
        @event_store = RailsEventStore::JSONClient.new
      end

      def call(measure, _retries, _run_id)
        concurrently do |writer_id, barrier|
          events =
            @batch_size.times.map do
              RubyEventStore::Event.new(
                metadata: {
                  event_type: "event_benchmarked",
                },
              )
            end
          barrier.wait

          measure.call do
            @event_store.append(
              events,
              stream_name: "writer:#{writer_id}",
              expected_version: :none,
            )
          end
        end
      end
    end
  end
end
