# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require "connection_pool"
require "pg_ephemeral"

require_relative "../en57"

module En57
  module Benchmark
    Result = Data.define(
      :name,
      :runs,
      :mean,
      :stddev,
      :min,
      :max,
      :median,
      :retry_count,
      :verified,
    )

    class Table
      def format(results)
        rows = results.select(&:verified)
        return "" if rows.empty?

        header = [
          "Scenario",
          "Runs",
          "Mean latency",
          "Stddev",
          "Min",
          "Max",
          "Median",
          "Retries",
        ]
        body =
          rows.map do |result|
            [
              result.name,
              result.runs.to_s,
              milliseconds(result.mean),
              milliseconds(result.stddev),
              milliseconds(result.min),
              milliseconds(result.max),
              milliseconds(result.median),
              result.retry_count.to_s,
            ]
          end
        widths = header.zip(*body).map { |values| values.map(&:length).max }
        rule = "+-#{widths.map { "-" * it }.join("-+-")}-+"

        [
          rule,
          table_row(header, widths, %i[left left left left left left left left]),
          rule,
          *body.map { table_row(it, widths, %i[left right right right right right right right]) },
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
        sorted_samples = samples.sort

        new(
          mean:,
          stddev:
            Math.sqrt(
              samples.sum { |sample| (sample - mean)**2 }.fdiv(samples.size),
            ),
          min: sorted_samples.first,
          max: sorted_samples.last,
          median:
            if samples.size.odd?
              sorted_samples[samples.size / 2]
            else
              (sorted_samples[(samples.size / 2) - 1] +
                sorted_samples[samples.size / 2]).fdiv(2)
            end,
        )
      end

      attr_reader :mean, :stddev, :min, :max, :median

      def initialize(mean:, stddev:, min:, max:, median:)
        @mean = mean
        @stddev = stddev
        @min = min
        @max = max
        @median = median
      end
    end

    class Scenario
      def initialize(
        name:,
        database_url:,
        measure:,
        runs:,
        warmup_runs:,
        concurrency:,
        batch_size:
      )
        @name = name
        @batch_size = batch_size
        @concurrency = concurrency
        @database_url = database_url
        @measure = measure
        @runs = runs
        @retry_count = Concurrent::AtomicFixnum.new(0)
        @warmup_runs = warmup_runs
      end

      attr_reader :name, :runs

      def retry_count = @retry_count.value

      def run
        warmup
        reset_retry_count
        @runs.times { call }
        verify
      end

      private

      def total_runs = @runs + @warmup_runs
      def call = nil
      def record_retry = @retry_count.increment
      def reset_retry_count = @retry_count.value = 0
      def verify = true
      def warmup = @warmup_runs.times { call }

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
      def self.classic(runs: 50)
        new(
          formatter: Table.new,
          scenarios: {
            "concurrent-append-non-conflicting-tags" => ->(
              database_url,
              warmup_runs,
              measure
            ) do
              ConcurrentAppendNonConflictingTags.new(
                name: "Concurrent append, non-conflicting tags",
                database_url:,
                measure:,
                warmup_runs:,
                runs:,
                concurrency: 10,
                batch_size: 100,
              )
            end,
            "concurrent-append-no-fail-if" => ->(database_url, warmup_runs, measure) do
              ConcurrentAppendNoFailIf.new(
                name: "Concurrent append, no fail_if",
                database_url:,
                measure:,
                warmup_runs:,
                runs:,
                concurrency: 10,
                batch_size: 100,
              )
            end,
            "concurrent-append-conflicting-tags" => ->(database_url, warmup_runs, measure) do
              ConcurrentAppendConflictingTags.new(
                name: "Concurrent append, conflicting tags",
                database_url:,
                measure:,
                warmup_runs:,
                runs:,
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
        results =
          @scenarios.map do |instance_name, mk_scenario|
            PgEphemeral.with_server(instance_name:) do |server|
              samples = []
              scenario =
                mk_scenario.call(
                  server.url,
                  warmup_runs = 2,
                  ->(&block) { samples << ::Benchmark.realtime { block.call } },
                )
              verified = scenario.run
              measurement = Measurement.from(samples.drop(warmup_runs))

              Result.new(
                name: scenario.name,
                runs: scenario.runs,
                mean: measurement.mean,
                stddev: measurement.stddev,
                min: measurement.min,
                max: measurement.max,
                median: measurement.median,
                retry_count: scenario.retry_count,
                verified:,
              )
            end
          end

        @formatter.format(results.select(&:verified))
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
              record_retry
              retry
            end
          end
        end
      end

      def verify =
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
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
              record_retry
              retry
            end
          end
        end
      end

      def verify =
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
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
              record_retry
              scope.each_with_position do |_event, event_position|
                position = event_position
              end
              retry
            end
          end
        end
      end

      def verify =
        @event_store.read.each.to_a.size ==
          total_runs * @concurrency * @batch_size
    end
  end
end
