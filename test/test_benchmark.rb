# frozen_string_literal: true

require "test_helper"
require "en57/benchmark"

module En57
  module Benchmark
    class TestBenchmark < Minitest::Test
      def test_table_formats_verified_results
        output =
          Table.new.format(
            [
              Result.new(
                name: "scenario",
                runs: 50,
                mean: 0.00123,
                stddev: 0.00045,
                min: 0.001,
                max: 0.002,
                median: 0.0015,
                retry_count: 12,
                verified: true,
              ),
            ],
          )

        assert_equal(<<~TABLE.chomp, output)
          +----------+------+--------------+---------+---------+---------+---------+---------+
          | Scenario | Runs | Mean latency | Stddev  | Min     | Max     | Median  | Retries |
          +----------+------+--------------+---------+---------+---------+---------+---------+
          | scenario |   50 |      1.23 ms | 0.45 ms | 1.00 ms | 2.00 ms | 1.50 ms |      12 |
          +----------+------+--------------+---------+---------+---------+---------+---------+
        TABLE
      end

      def test_table_omits_unverified_results
        assert_equal(
          "",
          Table.new.format(
            [
              Result.new(
                name: "scenario",
                runs: 50,
                mean: 0.00123,
                stddev: 0.00045,
                min: 0.001,
                max: 0.002,
                median: 0.0015,
                retry_count: 12,
                verified: false,
              ),
            ],
          ),
        )
      end

      def test_runner_formats_only_verified_results
        formatter = Object.new
        formatted_results = nil

        formatter.define_singleton_method(:format) do |results|
          formatted_results = results
          "formatted"
        end

        server = Data.define(:url).new("postgres://example")
        mk_scenario = ->(name, verified) do
          ->(_database_url, _warmup_runs, measure) do
            Data
              .define(:name, :runs, :measure, :verified, :retry_count) do
                def run
                  3.times { measure.call { nil } }
                  verified
                end
              end
              .new(name, 1, measure, verified, 3)
          end
        end

        output =
          PgEphemeral.stub(
            :with_server,
            ->(instance_name:, &block) { block.call(server) },
          ) do
            Runner.new(
              formatter:,
              scenarios: {
                "verified" => mk_scenario.call("verified", true),
                "unverified" => mk_scenario.call("unverified", false),
              },
            ).run
          end

        assert_equal("formatted", output)
        assert_equal(["verified"], formatted_results.map(&:name))
      end

      def test_runner_discards_two_warmup_measurements
        formatter = Object.new
        formatted_results = nil

        formatter.define_singleton_method(:format) do |results|
          formatted_results = results
          "formatted"
        end

        scenario_class =
          Class.new(Scenario) do
            def initialize(measure:, warmup_runs:)
              super(
                name: "warmup",
                database_url: "postgres://example",
                measure:,
                runs: 1,
                warmup_runs:,
                concurrency: 1,
                batch_size: 1,
              )
            end

            def call = @measure.call { nil }
          end
        server = Data.define(:url).new("postgres://example")
        durations = [0.1, 0.2, 0.3]

        PgEphemeral.stub(
          :with_server,
          ->(instance_name:, &block) { block.call(server) },
        ) do
          ::Benchmark.stub(
            :realtime,
            ->(&block) do
              block.call
              durations.shift
            end,
          ) do
            Runner.new(
              formatter:,
              scenarios: {
                "warmup" => ->(_database_url, warmup_runs, measure) do
                  scenario_class.new(measure:, warmup_runs:)
                end,
              },
            ).run
          end
        end

        assert_equal(0.3, formatted_results.fetch(0).mean)
      end

      def test_scenario_counts_retries_after_warmup
        scenario =
          Class
            .new(Scenario) do
              def initialize
                super(
                  name: "retrying",
                  database_url: "postgres://example",
                  measure: ->(&block) { block.call },
                  runs: 2,
                  warmup_runs: 1,
                  concurrency: 1,
                  batch_size: 1,
                )
              end

              def call = record_retry
            end
            .new

        assert_equal(true, scenario.run)
        assert_equal(2, scenario.retry_count)
      end

      def test_cli_lists_available_benchmark_names
        runner = Class.new { def self.names = %w[first second] }
        output = StringIO.new

        assert_equal(0, CLI.new(["list"], out: output, runner:).run)
        assert_equal("first\nsecond\n", output.string)
      end

      def test_cli_runs_all_benchmarks
        runner =
          Class.new do
            class << self
              attr_reader :classic_args
            end

            def self.classic(**kwargs)
              @classic_args = kwargs
              Data.define(:run).new("results")
            end
          end
        output = StringIO.new

        assert_equal(0, CLI.new(%w[run all], out: output, runner:, runs: 3).run)
        assert_equal({ runs: 3 }, runner.classic_args)
        assert_equal("results\n", output.string)
      end

      def test_cli_runs_named_benchmark
        runner =
          Class.new do
            class << self
              attr_reader :classic_args
            end

            def self.names = %w[one two]

            def self.classic(**kwargs)
              @classic_args = kwargs
              Data.define(:run).new("result")
            end
          end
        output = StringIO.new

        assert_equal(0, CLI.new(%w[run one], out: output, runner:, runs: 3).run)
        assert_equal({ runs: 3, names: ["one"] }, runner.classic_args)
        assert_equal("result\n", output.string)
      end

      def test_cli_rejects_unknown_benchmark_name
        runner = Class.new { def self.names = %w[one two] }
        error = StringIO.new

        assert_equal(
          1,
          CLI.new(%w[run unknown], err: error, runner:, runs: 3).run,
        )
        assert_equal("Unknown benchmark: unknown\n", error.string)
      end

      def test_measurement_calculates_summary_statistics
        measurement = Measurement.from([0.3, 0.1, 0.2])

        assert_in_delta(0.2, measurement.mean)
        assert_in_delta(0.08165, measurement.stddev, 0.00001)
        assert_in_delta(0.1, measurement.min)
        assert_in_delta(0.3, measurement.max)
        assert_in_delta(0.2, measurement.median)
      end

      def test_measurement_calculates_median_for_even_sample_counts
        measurement = Measurement.from([0.1, 0.2, 0.3, 0.4])

        assert_in_delta(0.25, measurement.median)
      end
    end
  end
end
