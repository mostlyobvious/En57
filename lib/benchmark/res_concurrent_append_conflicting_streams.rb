# frozen_string_literal: true

require "active_record"
require "rails_event_store"

module En57
  module Benchmark
    class ResConcurrentAppendConflictingStreams < Scenario
      def self.key = "res-concurrent-append-conflicting-streams"

      def self.build(database_url:, warmup_runs:, runs:)
        new(
          name: "10x100 concurrent append, conflicting streams (RES)",
          database_url:,
          warmup_runs:,
          runs:,
          concurrency: 10,
          batch_size: 100,
        )
      end

      def initialize(...)
        super
        ActiveRecord::Base.establish_connection(@database_url)
        @event_store = RailsEventStore::JSONClient.new
      end

      private

      def call(measure)
        type = "event_benchmarked"
        stream_name = "writer:#{SecureRandom.hex(4)}"
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          events =
            Array.new(@batch_size) do
              RubyEventStore::Event.new(metadata: { event_type: type })
            end
          position = -1

          barrier.wait

          measure.call do
            begin
              @event_store.append(
                events,
                stream_name: stream_name,
                expected_version: position,
              )
            rescue RubyEventStore::WrongExpectedEventVersion
              record_retry
              position = @event_store.read.stream(stream_name).count - 1
              retry
            end
          end
        end
        verify
      end

      def verify =
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
    end
  end
end
