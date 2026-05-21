# frozen_string_literal: true

require "test_helper"
require "en57/benchmark"

module En57
  module Benchmark
    class TestBenchmark < Minitest::Test
      cover "En57::Benchmark*"
      cover "En57::Benchmark::CLI#run"
      cover "En57::Benchmark::Scenario#concurrently"

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

      def test_table_right_aligns_numeric_columns
        output =
          Table.new.format(
            [
              Result.new(
                name: "a",
                runs: 1,
                mean: 0.001,
                stddev: 0.001,
                min: 0.001,
                max: 0.001,
                median: 0.001,
                retry_count: 1,
                verified: true,
              ),
              Result.new(
                name: "longer",
                runs: 100,
                mean: 0.001,
                stddev: 0.01,
                min: 0.01,
                max: 0.01,
                median: 0.01,
                retry_count: 100,
                verified: true,
              ),
            ],
          )

        assert_includes(
          output,
          "| a        |    1 |      1.00 ms |  1.00 ms |  1.00 ms |  1.00 ms |  1.00 ms |       1 |",
        )
        assert_includes(
          output,
          "| longer   |  100 |      1.00 ms | 10.00 ms | 10.00 ms | 10.00 ms | 10.00 ms |     100 |",
        )
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
        assert_equal([1], formatted_results.map(&:runs))
        assert_equal([3], formatted_results.map(&:retry_count))
      end

      def test_runner_uses_scenario_instance_names_and_database_urls
        formatter = Object.new
        formatter.define_singleton_method(:format) { |_results| "formatted" }
        server = Data.define(:url).new("postgres://example")
        instance_names = []
        database_urls = []
        measured_blocks = 0
        mk_scenario = ->(database_url, _warmup_runs, measure) do
          database_urls << database_url
          Class
            .new do
              define_method(:initialize) { @measure = measure }

              attr_reader :measure

              def name = "scenario"
              def retry_count = 0
              def runs = 1
              def run
                3.times { measure.call { @measured_blocks.call } }
                true
              end
            end
            .new
            .tap do
              it.instance_variable_set(
                :@measured_blocks,
                -> { measured_blocks += 1 },
              )
            end
        end

        PgEphemeral.stub(
          :with_server,
          ->(instance_name:, &block) do
            instance_names << instance_name
            block.call(server)
          end,
        ) do
          Runner.new(formatter:, scenarios: { "instance" => mk_scenario }).run
        end

        assert_equal(["instance"], instance_names)
        assert_equal(["postgres://example"], database_urls)
        assert_equal(3, measured_blocks)
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
                runs: 2,
                warmup_runs:,
                concurrency: 1,
                batch_size: 1,
              )
            end

            def call = @measure.call { nil }
          end
        server = Data.define(:url).new("postgres://example")
        durations = [0.1, 0.2, 0.3, 0.5]

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

        assert_equal(0.4, formatted_results.fetch(0).mean)
        assert_equal(0.1, formatted_results.fetch(0).stddev)
        assert_equal(0.3, formatted_results.fetch(0).min)
        assert_equal(0.5, formatted_results.fetch(0).max)
        assert_equal(0.4, formatted_results.fetch(0).median)
      end

      def test_scenario_calculates_total_runs
        scenario =
          Class
            .new(Scenario) do
              def initialize
                super(
                  name: "total",
                  database_url: "postgres://example",
                  measure: ->(&block) { block.call },
                  runs: 2,
                  warmup_runs: 3,
                  concurrency: 1,
                  batch_size: 1,
                )
              end

              def expose_total_runs = total_runs
            end
            .new

        assert_equal(5, scenario.expose_total_runs)
      end

      def test_scenario_defaults_to_noop_call
        scenario =
          Scenario.new(
            name: "noop",
            database_url: "postgres://example",
            measure: ->(&block) { block.call },
            runs: 1,
            warmup_runs: 1,
            concurrency: 1,
            batch_size: 1,
          )

        assert_equal(0, scenario.retry_count)
        assert_equal(true, scenario.run)
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

      def test_scenario_runs_blocks_concurrently
        calls = Concurrent::AtomicFixnum.new(0)
        scenario =
          Class
            .new(Scenario) do
              def initialize(calls)
                @calls = calls
                super(
                  name: "concurrent",
                  database_url: "postgres://example",
                  measure: ->(&block) { block.call },
                  runs: 1,
                  warmup_runs: 0,
                  concurrency: 1,
                  batch_size: 1,
                )
              end

              def call = concurrently(2) { @calls.increment }
            end
            .new(calls)

        assert_equal(true, scenario.run)
        assert_equal(2, calls.value)
      end

      def test_classic_runner_lists_benchmark_names
        assert_equal(
          %w[
            append-no-fail-if
            append-non-conflicting-tags
            concurrent-append-no-fail-if
            concurrent-append-non-conflicting-tags
            concurrent-append-non-conflicting-tags-seeded
            concurrent-append-conflicting-tags
          ],
          Runner.names,
        )
      end

      def test_classic_runner_builds_scenarios
        measure = ->(&block) { block.call }
        scenarios = Runner.classic.instance_variable_get(:@scenarios)

        [
          [
            "append-no-fail-if",
            AppendNoFailIf,
            "1x100 append, no fail_if",
            500,
            1,
          ],
          [
            "append-non-conflicting-tags",
            AppendNonConflictingTags,
            "1x100 append, non-conflicting tags",
            500,
            1,
          ],
          [
            "concurrent-append-no-fail-if",
            ConcurrentAppendNoFailIf,
            "10x100 concurrent append, no fail_if",
            50,
            10,
          ],
          [
            "concurrent-append-non-conflicting-tags",
            ConcurrentAppendNonConflictingTags,
            "10x100 concurrent append, non-conflicting tags",
            50,
            10,
          ],
          [
            "concurrent-append-non-conflicting-tags-seeded",
            ConcurrentAppendNonConflictingTagsSeeded,
            "10x100 concurrent append, non-conflicting tags (seeded)",
            50,
            10,
          ],
          [
            "concurrent-append-conflicting-tags",
            ConcurrentAppendConflictingTags,
            "10x100 concurrent append, conflicting tags",
            50,
            10,
          ],
        ].each do |key, scenario_class, name, runs, concurrency|
          scenario = scenarios.fetch(key).call("postgres://example", 2, measure)

          assert_instance_of(scenario_class, scenario)
          assert_equal(name, scenario.name)
          assert_equal(
            "postgres://example",
            scenario.instance_variable_get(:@database_url),
          )
          assert_same(measure, scenario.instance_variable_get(:@measure))
          assert_equal(2, scenario.instance_variable_get(:@warmup_runs))
          assert_equal(
            concurrency,
            scenario.instance_variable_get(:@concurrency),
          )
          assert_equal(100, scenario.instance_variable_get(:@batch_size))
          assert_equal(runs, scenario.runs)
        end
      end

      def test_classic_runner_selects_named_scenarios
        runner = Runner.classic(names: ["append-no-fail-if"])

        assert_equal(
          ["append-no-fail-if"],
          runner.instance_variable_get(:@scenarios).keys,
        )
      end

      def test_classic_runner_uses_table_formatter
        assert_instance_of(
          Table,
          Runner.classic.instance_variable_get(:@formatter),
        )
      end

      def test_cli_lists_available_benchmark_names
        runner = Class.new { def self.names = %w[first second] }
        output = StringIO.new

        Benchmark.stub_const(:Runner, runner) do
          assert_equal(0, CLI.new(["list"], out: output).run)
        end
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

        Benchmark.stub_const(:Runner, runner) do
          assert_equal(0, CLI.new(%w[run all], out: output, runs: 3).run)
        end
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

        Benchmark.stub_const(:Runner, runner) do
          assert_equal(0, CLI.new(%w[run one], out: output, runs: 3).run)
        end
        assert_equal({ runs: 3, names: ["one"] }, runner.classic_args)
        assert_equal("result\n", output.string)
      end

      def test_cli_rejects_unknown_benchmark_name
        runner = Class.new { def self.names = %w[one two] }
        error = StringIO.new

        Benchmark.stub_const(:Runner, runner) do
          assert_equal(1, CLI.new(%w[run unknown], err: error, runs: 3).run)
        end
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

      def test_measurement_calculates_median_for_larger_odd_sample_counts
        measurement = Measurement.from([0.1, 0.2, 0.3, 0.4, 0.5])

        assert_in_delta(0.3, measurement.median)
      end

      def test_measurement_calculates_median_for_larger_even_sample_counts
        measurement = Measurement.from([0.1, 0.2, 0.3, 0.4, 0.5, 0.6])

        assert_in_delta(0.35, measurement.median)
      end
    end

    class CLI::TestInitialize < Minitest::Test
      cover "En57::Benchmark::CLI#initialize"
      cover "En57::Benchmark::CLI#run"

      def test_defaults_to_stdout_stderr_runner_and_env_runs
        runner =
          Class.new do
            def self.names = ["default"]

            def self.classic(runs:, names:)
              Data.define(:run).new("#{runs.inspect}:#{names.fetch(0)}")
            end
          end

        output = StringIO.new
        error = StringIO.new

        Benchmark.stub_const(:Runner, runner) do
          $stdout = output
          $stderr = error

          ENV["BENCHMARK_RUNS"] = "7"
          assert_equal(0, CLI.new(%w[run default]).run)
        ensure
          $stdout = STDOUT
          ENV.delete("BENCHMARK_RUNS")
          $stderr = STDERR
        end

        assert_equal("7:default\n", output.string)
        assert_equal("", error.string)
      end

      def test_defaults_to_stderr
        output = StringIO.new
        error = StringIO.new

        $stdout = output
        $stderr = error

        assert_equal(1, CLI.new(["wat"]).run)
      ensure
        $stdout = STDOUT
        $stderr = STDERR

        assert_equal("", output.string)
        assert_equal(
          "Usage: benchmark list | benchmark run NAME | benchmark run all\n",
          error.string,
        )
      end

      def test_allows_stderr_override
        default_error = StringIO.new
        override_error = StringIO.new

        $stderr = default_error

        assert_equal(1, CLI.new(["wat"], err: override_error).run)
      ensure
        $stderr = STDERR

        assert_equal("", default_error.string)
        assert_equal(
          "Usage: benchmark list | benchmark run NAME | benchmark run all\n",
          override_error.string,
        )
      end

      def test_allows_stdout_override
        runner = Class.new { def self.names = %w[first second] }
        default_output = StringIO.new
        override_output = StringIO.new

        $stdout = default_output

        Benchmark.stub_const(:Runner, runner) do
          assert_equal(0, CLI.new(["list"], out: override_output).run)
        end
      ensure
        $stdout = STDOUT

        assert_equal("", default_output.string)
        assert_equal("first\nsecond\n", override_output.string)
      end

      def test_allows_runs_override
        runner =
          Class.new do
            class << self
              attr_reader :runs
            end

            def self.classic(runs:)
              @runs = runs
              Data.define(:run).new("result")
            end
          end

        Benchmark.stub_const(:Runner, runner) do
          assert_equal(0, CLI.new(%w[run all], out: StringIO.new, runs: 3).run)
        end
        assert_equal(3, runner.runs)
      end

      def test_stores_default_runner
        assert_same(Runner, CLI.new(["list"]).instance_variable_get(:@runner))
      end

      def test_defaults_runs_to_ten
        ENV.delete("BENCHMARK_RUNS")

        assert_equal(10, CLI.new(["list"]).instance_variable_get(:@runs))
      end
    end
  end
end
