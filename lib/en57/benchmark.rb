# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require "connection_pool"
require "pg_ephemeral"
require "securerandom"

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
      )

    class Table
      def format(results)
        return "" if results.empty?

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
          results.map do |result|
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
      Configuration =
        Data.define(:database_instance, :name, :concurrency, :batch_size, :runs)

      @definitions = []

      def self.definitions = @definitions

      def self.define(
        database_instance:,
        name:,
        concurrency: 1,
        batch_size: 100,
        runs: ->(runs) { runs },
        &block
      )
        register(
          Configuration.new(
            database_instance:,
            name:,
            concurrency:,
            batch_size:,
            runs:,
          ),
          &block
        )
      end

      def self.with(**overrides) = register(configuration.with(**overrides))

      def self.register(configuration, &block)
        Class
          .new(self) do
            define_singleton_method(:configuration) { configuration }

            define_singleton_method(:database_instance) do
              configuration.database_instance
            end

            define_singleton_method(
              :build,
            ) do |database_url:, warmup_runs:, runs:|
              new(
                name: configuration.name,
                database_url:,
                runs: configuration.runs.call(runs),
                warmup_runs:,
                concurrency: configuration.concurrency,
                batch_size: configuration.batch_size,
              )
            end

            class_eval(&block) if block
          end
          .tap { Scenario.definitions << it }
      end
      private_class_method :register

      def initialize(
        name:,
        database_url:,
        runs:,
        warmup_runs:,
        concurrency:,
        batch_size:
      )
        @name = name
        @batch_size = batch_size
        @concurrency = concurrency
        @database_url = database_url
        @runs = runs
        @retry_count = Concurrent::AtomicFixnum.new
        @warmup_runs = warmup_runs
        setup(database_url)
      end

      attr_reader :name, :runs

      def retry_count = @retry_count.value

      NOOP_MEASURE = ->(&block) { block.call }

      def run(measure)
        warmup
        reset_retry_count
        @runs.times { call(measure, SecureRandom.hex(4)) }
      end

      private

      def total_runs = @runs + @warmup_runs
      def setup(_database_url)
      end
      def call(_measure, _run_id)
      end
      def record_retry = @retry_count.increment
      def reset_retry_count = @retry_count.value = 0
      def warmup
        @warmup_runs.times { call(NOOP_MEASURE, SecureRandom.hex(4)) }
      end

      def concurrently
        barrier = Concurrent::CyclicBarrier.new(@concurrency)
        Array
          .new(@concurrency) do
            Thread.new { yield SecureRandom.hex(4), barrier }
          end
          .each(&:value)
      end
    end

    Dir[File.expand_path("../benchmark/*.rb", __dir__)].sort.each do |path|
      require path
    end

    class Runner
      def self.classic(runs: 50, names: nil)
        selected_scenarios = scenarios(runs:)
        selected_scenarios = selected_scenarios.slice(*names) if names

        new(formatter: Table.new, scenarios: selected_scenarios)
      end

      def self.names = scenarios(runs: nil).keys

      def self.scenarios(runs:)
        Scenario
          .definitions
          .sort_by(&:database_instance)
          .to_h do |scenario_class|
            [
              scenario_class.database_instance,
              ->(database_url, warmup_runs) do
                scenario_class.build(database_url:, warmup_runs:, runs:)
              end,
            ]
          end
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
              scenario = mk_scenario.call(server.url, 2)
              scenario.run(
                ->(&block) { samples << ::Benchmark.realtime { block.call } },
              )
              measurement = Measurement.from(samples)

              Result.new(
                name: scenario.name,
                runs: scenario.runs,
                mean: measurement.mean,
                stddev: measurement.stddev,
                min: measurement.min,
                max: measurement.max,
                median: measurement.median,
                retry_count: scenario.retry_count,
              )
            end
          end

        @formatter.format(results)
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
