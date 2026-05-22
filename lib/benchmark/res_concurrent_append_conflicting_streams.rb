# frozen_string_literal: true

require "active_record"
require "rails_event_store"

module En57
  module Benchmark
    Scenario.define do
      database_instance "res-concurrent-append-conflicting-streams"
      name "10x100 concurrent append, conflicting streams (RES)"
      concurrency 10
      batch_size 100

      setup do |database_url|
        ActiveRecord::Base.establish_connection(database_url)
        @event_store = RailsEventStore::JSONClient.new
      end

      call do |measure|
        type = "event_benchmarked"
        stream_name = "writer:#{SecureRandom.hex(4)}"
        concurrently do |barrier|
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
      end
    end
  end
end
