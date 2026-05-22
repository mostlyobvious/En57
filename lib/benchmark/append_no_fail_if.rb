# frozen_string_literal: true

module En57
  module Benchmark
    class AppendNoFailIf < Scenario
      def self.key = "append-no-fail-if"

      def self.build(database_url:, warmup_runs:, runs:)
        new(
          name: "1x100 append, no fail_if",
          database_url:,
          warmup_runs:,
          runs: runs * 10,
          concurrency: 1,
          batch_size: 100,
        )
      end

      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call(measure)
        type = "event_benchmarked"
        tags = %W[writer:#{SecureRandom.hex(4)}]
        events =
          Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

        measure.call { @event_store.append(events) }
        verify
      end

      def verify = @event_store.read.each.to_a.size == total_runs * @batch_size
    end
  end
end
