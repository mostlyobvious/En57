# frozen_string_literal: true

require "active_record"
require "rails_event_store"

module En57
  module Benchmark
    Scenario.define do
      database_instance "res-append-stream-any"
      name "1x100 append, expected_version :any (RES)"
      runs { it * 10 }
      concurrency 1
      batch_size 100

      setup do |database_url|
        ActiveRecord::Base.establish_connection(database_url)
        @event_store = RailsEventStore::JSONClient.new
      end

      call do |measure|
        type = "event_benchmarked"
        tag = "writer:#{SecureRandom.hex(4)}"
        events =
          Array.new(@batch_size) do
            RubyEventStore::Event.new(metadata: { event_type: type })
          end

        measure.call do
          @event_store.append(events, stream_name: tag, expected_version: :any)
        end
      end

      verify { @event_store.read.each.to_a.size == total_runs * @batch_size }
    end
  end
end
