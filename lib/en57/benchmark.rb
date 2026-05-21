# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require "connection_pool"
require "pg_ephemeral"

require_relative "../en57"

module En57
  module Benchmark
    Result =
      Data.define(
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
          table_row(header, widths, []),
          rule,
          body.map do
            table_row(
              it,
              widths,
              [nil, true, true, true, true, true, true, true],
            )
          end,
          rule,
        ].join("\n")
      end

      private

      def table_row(values, widths, alignments)
        cells =
          values
            .zip(widths, alignments)
            .map do |value, width, alignment|
              alignment ? value.rjust(width) : value.ljust(width)
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
              sorted_samples.fetch(samples.size / 2)
            else
              (
                sorted_samples.fetch((samples.size / 2) - 1) +
                  sorted_samples.fetch(samples.size / 2)
              ).fdiv(2)
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
        @retry_count = Concurrent::AtomicFixnum.new
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
      def call
      end
      def record_retry = @retry_count.increment
      def reset_retry_count = @retry_count.value = 0
      def verify = true
      def warmup = @warmup_runs.times { call }

      def concurrently(concurrency)
        Array.new(concurrency) { Thread.new { yield } }.each(&:value)
      end
    end

    require_relative "../benchmark/append_no_fail_if"
    require_relative "../benchmark/append_non_conflicting_tags"
    require_relative "../benchmark/concurrent_append_no_fail_if"
    require_relative "../benchmark/concurrent_append_non_conflicting_tags"
    require_relative "../benchmark/concurrent_append_non_conflicting_tags_seeded"
    require_relative "../benchmark/concurrent_append_conflicting_tags"

    class Runner
      def self.classic(runs: 50, names: nil)
        selected_scenarios = scenarios(runs:)
        selected_scenarios = selected_scenarios.slice(*names) if names

        new(formatter: Table.new, scenarios: selected_scenarios)
      end

      def self.names = scenarios(runs: nil).keys

      def self.scenarios(runs:)
        {
          "append-no-fail-if" => ->(database_url, warmup_runs, measure) do
            AppendNoFailIf.new(
              name: "Append, no fail_if",
              database_url:,
              measure:,
              warmup_runs:,
              runs: runs * 10,
              concurrency: 1,
              batch_size: 100,
            )
          end,
          "append-non-conflicting-tags" => ->(
            database_url,
            warmup_runs,
            measure
          ) do
            AppendNonConflictingTags.new(
              name: "Append, non-conflicting tags",
              database_url:,
              measure:,
              warmup_runs:,
              runs: runs * 10,
              concurrency: 1,
              batch_size: 100,
            )
          end,
          "concurrent-append-no-fail-if" => ->(
            database_url,
            warmup_runs,
            measure
          ) do
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
          "concurrent-append-non-conflicting-tags-seeded" => ->(
            database_url,
            warmup_runs,
            measure
          ) do
            ConcurrentAppendNonConflictingTagsSeeded.new(
              name: "Concurrent append, non-conflicting tags (seeded)",
              database_url:,
              measure:,
              warmup_runs:,
              runs:,
              concurrency: 10,
              batch_size: 100,
            )
          end,
          "concurrent-append-conflicting-tags" => ->(
            database_url,
            warmup_runs,
            measure
          ) do
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
        }
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

    class CLI
      def initialize(argv, out: nil, err: nil, runs: nil)
        @argv = argv
        @err = err || $stderr
        @out = out || $stdout
        @runner = Runner
        @runs = runs || Integer(ENV.fetch("BENCHMARK_RUNS", 10))
      end

      def run
        case @argv
        in ["list"]
          @out.puts(@runner.names)
          0
        in ["run", "all"]
          @out.puts(@runner.classic(runs: @runs).run)
          0
        in ["run", name]
          return unknown(name) unless @runner.names.include?(name)

          @out.puts(@runner.classic(runs: @runs, names: [name]).run)
          0
        else
          @err.puts(
            "Usage: benchmark list | benchmark run NAME | benchmark run all",
          )
          1
        end
      end

      private

      def unknown(name)
        @err.puts("Unknown benchmark: #{name}")
        1
      end
    end
  end
end
