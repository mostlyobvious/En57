# frozen_string_literal: true

require "active_record"
require "rails_event_store"

module En57
  module Benchmark
    class ResConcurrentAppendNonConflictingStreams < Scenario
      def self.key = "res-concurrent-append-non-conflicting-streams"

      def self.build(database_url:, warmup_runs:, runs:)
        new(
          name: "10x100 concurrent append, non-conflicting streams (RES)",
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
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          tag = "writer:#{SecureRandom.hex(4)}"
          @event_store.read.stream(tag).of_type(type)
          events =
            Array.new(@batch_size) do
              RubyEventStore::Event.new(metadata: { event_type: type })
            end

          barrier.wait

          measure.call do
            @event_store.append(
              events,
              stream_name: tag,
              expected_version: :none,
            )
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
