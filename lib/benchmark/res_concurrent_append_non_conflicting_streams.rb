# frozen_string_literal: true

require "active_record"
require "rails_event_store"

module En57
  module Benchmark
    Scenario.define do
      database_instance "res-concurrent-append-non-conflicting-streams"
      name "10x100 concurrent append, non-conflicting streams (RES)"
      concurrency 10
      batch_size 100

      setup do |database_url|
        ActiveRecord::Base.establish_connection(database_url)
        @event_store = RailsEventStore::JSONClient.new
      end

      call do |measure|
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
      end

      verify do
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
      end
    end
  end
end
