# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require "connection_pool"
require "pg_ephemeral"

require_relative "../en57"

module En57
  module Benchmark
    Result = Data.define(:name, :runs, :mean, :stddev, :verified)

    class Table
      def format(results)
        rows = results.select(&:verified)
        return "" if rows.empty?

        header = ["Scenario", "Runs", "Mean latency", "Stddev"]
        body =
          rows.map do |result|
            [
              result.name,
              result.runs.to_s,
              milliseconds(result.mean),
              milliseconds(result.stddev),
            ]
          end
        widths = header.zip(*body).map { |values| values.map(&:length).max }
        rule = "+-#{widths.map { "-" * it }.join("-+-")}-+"

        [
          rule,
          table_row(header, widths, %i[left left left left]),
          rule,
          *body.map { table_row(it, widths, %i[left right right right]) },
          rule,
        ].join("\n")
      end

      private

      def table_row(values, widths, alignments)
        cells =
          values
            .zip(widths, alignments)
            .map do |value, width, alignment|
              alignment == :right ? value.rjust(width) : value.ljust(width)
            end

        "| #{cells.join(" | ")} |"
      end

      def milliseconds(seconds) = Kernel.format("%.2f ms", seconds * 1000)
    end

    class Measurement
      def self.from(samples)
        mean = samples.sum.fdiv(samples.size)

        new(
          mean:,
          stddev:
            Math.sqrt(
              samples.sum { |sample| (sample - mean)**2 }.fdiv(samples.size),
            ),
        )
      end

      attr_reader :mean, :stddev

      def initialize(mean:, stddev:)
        @mean = mean
        @stddev = stddev
      end
    end

    class Scenario
      def initialize(
        name:,
        database_url:,
        measure:,
        runs:,
        concurrency:,
        batch_size:
      )
        @name = name
        @batch_size = batch_size
        @concurrency = concurrency
        @database_url = database_url
        @measure = measure
        @runs = runs
      end

      attr_reader :name, :runs

      def run
        @runs.times { call }
        verify
      end

      private

      def call = nil
      def verify = true

      def concurrently(concurrency)
        Array
          .new(concurrency) do
            Thread.new do
              Thread.report_on_exception = false
              yield
            end
          end
          .each(&:join)
      end
    end

    class Runner
      def self.classic
        new(
          formatter: Table.new,
          scenarios: {
            "concurrent-append-non-conflicting-tags" => ->(
              database_url,
              measure
            ) do
              ConcurrentAppendNonConflictingTags.new(
                name: "Concurrent append, non-conflicting tags",
                database_url:,
                measure:,
                runs: ENV.fetch("BENCHMARK_RUNS", 1),
                concurrency: 10,
                batch_size: 100,
              )
            end,
            "concurrent-append-no-fail-if" => ->(database_url, measure) do
              ConcurrentAppendNoFailIf.new(
                name: "Concurrent append, no fail_if",
                database_url:,
                measure:,
                runs: ENV.fetch("BENCHMARK_RUNS", 1),
                concurrency: 10,
                batch_size: 100,
              )
            end,
            "concurrent-append-conflicting-tags" => ->(database_url, measure) do
              ConcurrentAppendConflictingTags.new(
                name: "Concurrent append, conflicting tags",
                database_url:,
                measure:,
                runs: ENV.fetch("BENCHMARK_RUNS", 1),
                concurrency: 10,
                batch_size: 100,
              )
            end,
          },
        )
      end

      def initialize(scenarios:, formatter:)
        @formatter = formatter
        @scenarios = scenarios
      end

      def run
        @formatter.format(
          @scenarios.map do |instance_name, mk_scenario|
            PgEphemeral.with_server(instance_name:) do |server|
              samples = []
              scenario =
                mk_scenario.call(
                  server.url,
                  ->(&block) { samples << ::Benchmark.realtime { block.call } },
                )
              verified = scenario.run
              measurement = Measurement.from(samples)

              Result.new(
                name: scenario.name,
                runs: scenario.runs,
                mean: measurement.mean,
                stddev: measurement.stddev,
                verified:,
              )
            end
          end,
        )
      end
    end

    class ConcurrentAppendNoFailIf < Scenario
      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call
        type = "event_benchmarked"
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          tags = %W[writer:#{SecureRandom.hex(4)}]
          events =
            Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

          barrier.wait

          @measure.call do
            begin
              @event_store.append(events)
            rescue AppendConditionViolated
              retry
            end
          end
        end
      end

      def verify =
        @event_store.read.each.to_a.size == @runs * @concurrency * @batch_size
    end

    class ConcurrentAppendNonConflictingTags < Scenario
      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call
        type = "event_benchmarked"
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          tags = %W[writer:#{SecureRandom.hex(4)}]
          scope = @event_store.read.of_type(type).with_tag(tags)
          events =
            Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }

          barrier.wait

          @measure.call do
            begin
              @event_store.append(events, fail_if: scope.after(position = 0))
            rescue AppendConditionViolated
              retry
            end
          end
        end
      end

      def verify =
        @event_store.read.each.to_a.size == @runs * @concurrency * @batch_size
    end

    class ConcurrentAppendConflictingTags < Scenario
      def initialize(...)
        super
        @event_store =
          EventStore.for_pooled_pg(@database_url, max_connections: @concurrency)
      end

      private

      def call
        type = "event_benchmarked"
        tags = %W[writer:#{SecureRandom.hex(4)}]
        barrier = Concurrent::CyclicBarrier.new(@concurrency)

        concurrently(@concurrency) do
          scope = @event_store.read.of_type(type).with_tag(tags)
          events =
            Array.new(@batch_size) { En57::Event.new(type: type, tags: tags) }
          position = 0

          barrier.wait

          @measure.call do
            begin
              @event_store.append(events, fail_if: scope.after(position))
            rescue AppendConditionViolated
              scope.each_with_position { |_event, event_position| position = event_position }
              retry
            end
          end
        end
      end

      def verify =
        @event_store.read.each.to_a.size == @runs * @concurrency * @batch_size
    end
  end
end
