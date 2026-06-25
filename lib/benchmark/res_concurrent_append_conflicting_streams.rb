# frozen_string_literal: true

module En57
  module Benchmark
    Scenario.define(
      database_instance: "res-concurrent-append-conflicting-streams",
      name: "10x100 concurrent append, conflicting streams (RES)",
      concurrency: 10,
      batch_size: 100,
      template: "golden_res",
    ) do
      def setup(database_url)
        require "active_record"
        require "rails_event_store"

        ActiveRecord::Base.establish_connection(
          url: database_url,
          pool: @concurrency,
        )
        @event_store = RailsEventStore::JSONClient.new
      end

      def call(measure, retries, run_id)
        concurrently do |_writer_id, barrier|
          stream_name = "writer:#{run_id}"
          events =
            @batch_size.times.map do
              RubyEventStore::Event.new(
                metadata: {
                  event_type: "event_benchmarked",
                },
              )
            end
          expected_version = -1
          barrier.wait

          measure.call do
            begin
              @event_store.append(events, stream_name:, expected_version:)
            rescue RubyEventStore::WrongExpectedEventVersion
              retries.call
              expected_version = @event_store.read.stream(stream_name).count - 1
              retry
            end
          end
        end
      end
    end
  end
end
