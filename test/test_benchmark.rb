# frozen_string_literal: true

require "test_helper"
require "en57/benchmark"

module En57
  module Benchmark
    class TestBenchmark < Minitest::Test
      cover "En57::Benchmark*"
      cover "En57::Benchmark::CLI#run"
      cover "En57::Benchmark::Scenario#concurrently"

      def test_table_formats_results
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

      def test_table_formats_empty_results
        assert_equal("", Table.new.format([]))
      end

      def test_runner_formats_results
        formatter = Object.new
        formatted_results = nil

        formatter.define_singleton_method(:format) do |results|
          formatted_results = results
          "formatted"
        end

        mk_scenario = ->(name) do
          Runnable.new(
            reset: "",
            build: ->(_database_url, _warmup_runs) do
              Data
                .define(:name, :runs, :retry_count) do
                  def run(measure, retries)
                    3.times do
                      retries.call
                      measure.call { nil }
                    end
                  end
                end
                .new(name, 1, 3)
            end,
          )
        end

        output =
          PG.stub(:connect, fake_pg_connection.method(:connect)) do
            Runner.new(
              formatter:,
              scenarios: {
                "first" => mk_scenario.call("first"),
                "second" => mk_scenario.call("second"),
              },
            ).run
          end

        assert_equal("formatted", output)
        assert_equal(%w[first second], formatted_results.map(&:name))
        assert_equal([1, 1], formatted_results.map(&:runs))
        assert_equal([3, 3], formatted_results.map(&:retry_count))
      end

      def test_runner_sets_append_retries_during_benchmark
        formatter = Object.new
        formatter.define_singleton_method(:format) { |_results| "formatted" }
        append_retries = nil
        original_append_retries = En57.configuration.append_retries
        En57.configuration.append_retries = 7
        scenario =
          Class
            .new do
              def initialize(capture)
                @capture = capture
              end

              def name = "scenario"
              def runs = 1
              def run(measure, _retries)
                @capture.call(En57.configuration.append_retries)
                measure.call { nil }
              end
            end
            .new(->(value) { append_retries = value })

        PG.stub(:connect, fake_pg_connection.method(:connect)) do
          Runner.new(
            formatter:,
            scenarios: {
              "instance" =>
                Runnable.new(
                  reset: "",
                  build: ->(_database_url, _warmup_runs) { scenario },
                ),
            },
          ).run
        end

        assert_equal(100, append_retries)
        assert_equal(7, En57.configuration.append_retries)
      ensure
        En57.configuration.append_retries = original_append_retries
      end

      def test_runner_uses_concurrent_array_for_samples
        formatter = Object.new
        formatted_results = nil
        formatter.define_singleton_method(:format) do |results|
          formatted_results = results
        end
        samples =
          Class
            .new(Array) do
              def <<(sample)
                super(sample + 1)
              end
            end
            .new
        scenario =
          Class
            .new do
              def name = "scenario"
              def runs = 2
              def run(measure, _retries)
                2.times { measure.call { nil } }
              end
            end
            .new

        PG.stub(:connect, fake_pg_connection.method(:connect)) do
          Concurrent::Array.stub(:new, samples) do
            ::Benchmark.stub(:realtime, ->(&block) { block.call || 0.1 }) do
              Runner.new(
                formatter:,
                scenarios: {
                  "instance" =>
                    Runnable.new(
                      reset: "",
                      build: ->(_database_url, _warmup_runs) { scenario },
                    ),
                },
              ).run
            end
          end
        end

        assert_in_delta(1.1, formatted_results.fetch(0).mean)
      end

      def test_runner_resets_database_and_uses_instance_database_urls
        formatter = Object.new
        formatter.define_singleton_method(:format) { |_results| "formatted" }
        database_urls = []
        warmup_runs = []
        measured_blocks = 0
        build = ->(database_url, warmup_run_count) do
          database_urls << database_url
          warmup_runs << warmup_run_count
          Class
            .new do
              def name = "scenario"
              def retry_count = 0
              def runs = 1
              def run(measure, _retries)
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

        connection = fake_pg_connection
        PG.stub(:connect, connection.method(:connect)) do
          Runner.new(
            formatter:,
            scenarios: {
              "instance" => Runnable.new(reset: "RESET SQL", build:),
            },
          ).run
        end

        assert_equal(["postgres:///instance"], database_urls)
        assert_equal([2], warmup_runs)
        assert_equal(3, measured_blocks)
        assert_equal(["postgres:///instance"], connection.urls)
        assert_equal(["RESET SQL"], connection.statements)
        assert_equal(1, connection.closed)
      end

      def test_runner_propagates_reset_connection_errors_without_masking
        formatter = Object.new
        formatter.define_singleton_method(:format) { |_results| "formatted" }
        boom = Class.new(StandardError)

        error =
          assert_raises(boom) do
            PG.stub(:connect, ->(_url) { raise boom }) do
              Runner.new(
                formatter:,
                scenarios: {
                  "instance" =>
                    Runnable.new(
                      reset: "",
                      build: ->(_database_url, _warmup_runs) { nil },
                    ),
                },
              ).run
            end
          end

        assert_instance_of(boom, error)
      end

      def test_scenario_uses_noop_measure_for_warmup
        formatter = Object.new
        formatted_results = nil

        formatter.define_singleton_method(:format) do |results|
          formatted_results = results
          "formatted"
        end

        scenario_class =
          Class.new(Scenario) do
            attr_reader :call_count

            def initialize(warmup_runs:)
              @call_count = 0
              super(
                name: "warmup",
                database_url: "postgres://example",
                runs: 2,
                warmup_runs:,
                concurrency: 1,
                batch_size: 1,
              )
            end

            def call(measure, _retries, _run_id)
              @call_count += 1
              measure.call { nil }
              true
            end
          end
        scenario = nil
        durations = [0.1, 0.2]

        PG.stub(:connect, fake_pg_connection.method(:connect)) do
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
                "warmup" =>
                  Runnable.new(
                    reset: "",
                    build: ->(_database_url, warmup_runs) do
                      scenario = scenario_class.new(warmup_runs:)
                    end,
                  ),
              },
            ).run
          end
        end

        assert_equal(4, scenario.call_count)
        assert_in_delta(0.15, formatted_results.fetch(0).mean)
        assert_in_delta(0.05, formatted_results.fetch(0).stddev)
        assert_equal(0.1, formatted_results.fetch(0).min)
        assert_equal(0.2, formatted_results.fetch(0).max)
        assert_in_delta(0.15, formatted_results.fetch(0).median)
      end

      def test_scenario_define_registers_configured_scenario
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(
            database_instance: "defined",
            name: "Defined scenario",
            runs: ->(runs) { runs * 2 },
            concurrency: 2,
            batch_size: 3,
          ) do
            def setup(_database_url)
              @setup_called = true
            end

            def call(measure, _retries, _run_id)
              measure.call { @call_measured = true }
              nil
            end
          end
        scenario =
          scenario_class.build(
            database_url: "postgres://example",
            warmup_runs: 0,
            runs: 4,
          )

        assert_includes(Scenario.definitions, scenario_class)
        assert_equal("defined", scenario_class.database_instance)
        assert_equal("Defined scenario", scenario.name)
        assert_equal(
          "postgres://example",
          scenario.instance_variable_get(:@database_url),
        )
        assert_equal(8, scenario.runs)
        assert_equal(2, scenario.instance_variable_get(:@concurrency))
        assert_equal(3, scenario.instance_variable_get(:@batch_size))
        scenario.run(->(&block) { block.call }, -> {})

        assert_equal(true, scenario.instance_variable_get(:@call_measured))
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_scenario_define_yields_database_url_to_setup
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(
            database_instance: "setup-database-url",
            name: "Setup database URL",
          ) do
            def setup(database_url)
              @setup_database_url = database_url
            end
          end
        scenario =
          scenario_class.build(
            database_url: "postgres://example",
            warmup_runs: 0,
            runs: 1,
          )

        assert_equal(
          "postgres://example",
          scenario.instance_variable_get(:@setup_database_url),
        )
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_scenario_define_defaults
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(
            database_instance: "defaulted",
            name: "Defaulted scenario",
          )
        scenario =
          scenario_class.build(
            database_url: "postgres://example",
            warmup_runs: 0,
            runs: 7,
          )

        assert_equal(7, scenario.runs)
        assert_equal(1, scenario.instance_variable_get(:@concurrency))
        assert_equal(100, scenario.instance_variable_get(:@batch_size))
        scenario.run(->(&block) { block.call }, -> {})
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_scenario_with_registers_a_copy_with_overridden_configuration
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(
            database_instance: "original",
            name: "Original scenario",
            concurrency: 2,
            batch_size: 5,
          ) do
            def setup(database_url)
              @setup_database_url = database_url
            end

            def call(measure, _retries, _run_id)
              measure.call { @called = true }
            end
          end

        copy = scenario_class.with(database_instance: "copy", name: "Copy")
        scenario =
          copy.build(
            database_url: "postgres://example",
            warmup_runs: 0,
            runs: 1,
          )

        assert_includes(Scenario.definitions, copy)
        refute_same(scenario_class, copy)
        assert_equal("original", scenario_class.database_instance)
        assert_equal("copy", copy.database_instance)
        assert_equal("Copy", scenario.name)
        assert_equal(2, scenario.instance_variable_get(:@concurrency))
        assert_equal(5, scenario.instance_variable_get(:@batch_size))
        assert_equal(
          "postgres://example",
          scenario.instance_variable_get(:@setup_database_url),
        )
        scenario.run(->(&block) { block.call }, -> {})

        assert_equal(true, scenario.instance_variable_get(:@called))
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_scenario_stores_configuration
        scenario =
          Scenario.new(
            name: "configured",
            database_url: "postgres://example",
            runs: 1,
            warmup_runs: 1,
            concurrency: 2,
            batch_size: 3,
          )

        assert_equal("configured", scenario.name)
        assert_equal(
          "postgres://example",
          scenario.instance_variable_get(:@database_url),
        )
        assert_equal(2, scenario.instance_variable_get(:@concurrency))
        assert_equal(3, scenario.instance_variable_get(:@batch_size))
      end

      def test_scenario_defaults_to_noop_call
        scenario =
          Scenario.new(
            name: "noop",
            database_url: "postgres://example",
            runs: 1,
            warmup_runs: 1,
            concurrency: 1,
            batch_size: 1,
          )

        scenario.run(->(&block) { block.call }, -> {})
      end

      def test_scenario_runs_when_no_measured_runs
        scenario =
          Scenario.new(
            name: "empty",
            database_url: "postgres://example",
            runs: 0,
            warmup_runs: 0,
            concurrency: 1,
            batch_size: 1,
          )

        scenario.run(->(&block) { block.call }, -> {})
      end

      def test_scenario_define_yields_run_id_to_call
        original_definitions = Scenario.definitions.dup
        run_ids = []
        scenario_class =
          Scenario.define(
            database_instance: "defined-run-id",
            name: "Defined run ID",
          ) do
            define_method(:call) do |_measure, _retries, run_id|
              run_ids << run_id
            end
          end
        scenario =
          scenario_class.build(
            database_url: "postgres://example",
            warmup_runs: 1,
            runs: 2,
          )

        scenario.run(->(&block) { block.call }, -> {})

        assert_equal(3, run_ids.size)
        assert_equal(3, run_ids.uniq.size)
        run_ids.each { |run_id| assert_match(/\A\h{8}\z/, run_id) }
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_scenario_yields_run_id_to_call
        run_ids = []
        scenario =
          Class
            .new(Scenario) do
              def initialize(run_ids)
                @run_ids = run_ids
                super(
                  name: "run-id",
                  database_url: "postgres://example",
                  runs: 2,
                  warmup_runs: 1,
                  concurrency: 1,
                  batch_size: 1,
                )
              end

              def call(_measure, _retries, run_id)
                @run_ids << run_id
              end
            end
            .new(run_ids)

        scenario.run(->(&block) { block.call }, -> {})

        assert_equal(3, run_ids.size)
        assert_equal(3, run_ids.uniq.size)
        run_ids.each { |run_id| assert_match(/\A\h{8}\z/, run_id) }
      end

      def test_scenario_counts_retries_after_warmup
        retry_count = Concurrent::AtomicFixnum.new
        scenario =
          Class
            .new(Scenario) do
              def initialize
                super(
                  name: "retrying",
                  database_url: "postgres://example",
                  runs: 2,
                  warmup_runs: 1,
                  concurrency: 1,
                  batch_size: 1,
                )
              end

              def call(_measure, retries, _run_id)
                retries.call
                true
              end
            end
            .new

        scenario.run(->(&block) { block.call }, -> { retry_count.increment })

        assert_equal(2, retry_count.value)
      end

      def test_scenario_runs_blocks_concurrently
        calls = Concurrent::AtomicFixnum.new(0)
        barriers = Queue.new
        writer_ids = Queue.new
        scenario =
          Class
            .new(Scenario) do
              def initialize(calls, barriers, writer_ids)
                @barriers = barriers
                @calls = calls
                @writer_ids = writer_ids
                super(
                  name: "concurrent",
                  database_url: "postgres://example",
                  runs: 1,
                  warmup_runs: 0,
                  concurrency: 2,
                  batch_size: 1,
                )
              end

              def call(_measure, _retries, _run_id)
                concurrently do |writer_id, barrier|
                  @barriers << barrier
                  @writer_ids << writer_id
                  barrier.wait
                  @calls.increment
                end
              end
            end
            .new(calls, barriers, writer_ids)

        scenario.run(->(&block) { block.call }, -> {})

        assert_equal(2, calls.value)
        assert_equal(1, 2.times.map { barriers.pop }.uniq.size)

        received_writer_ids = 2.times.map { writer_ids.pop }
        assert_equal(2, received_writer_ids.uniq.size)
        received_writer_ids.each do |writer_id|
          assert_match(/\A\h{8}\z/, writer_id)
        end
      end

      def test_runner_discovers_scenarios_by_database_instance
        first_scenario =
          Class.new do
            def self.database_instance = "a-discovered"
            def self.reset = "reset-a"

            def self.build(database_url:, warmup_runs:, runs:)
              [database_url, warmup_runs, runs]
            end
          end
        second_scenario =
          Class.new do
            def self.database_instance = "b-discovered"
            def self.reset = "reset-b"

            def self.build(database_url:, warmup_runs:, runs:)
              [database_url, warmup_runs, runs]
            end
          end

        Scenario.stub(:definitions, [second_scenario, first_scenario]) do
          assert_equal(%w[a-discovered b-discovered], Runner.names)
          runnable = Runner.scenarios(runs: 3).fetch("a-discovered")
          assert_equal("reset-a", runnable.reset)
          assert_equal(
            ["postgres://example", 2, 3],
            runnable.build.call("postgres://example", 2),
          )
        end
      end

      def test_classic_runner_selects_named_scenarios
        first_scenario =
          Class.new do
            def self.database_instance = "first"
            def self.reset = ""
            def self.build(...) = nil
          end
        second_scenario =
          Class.new do
            def self.database_instance = "second"
            def self.reset = ""
            def self.build(...) = nil
          end

        Scenario.stub(:definitions, [first_scenario, second_scenario]) do
          runner = Runner.classic(names: ["first"])

          assert_equal(
            ["first"],
            runner.instance_variable_get(:@scenarios).keys,
          )
        end
      end

      def test_classic_runner_defaults_to_fifty_runs
        scenario =
          Class.new do
            def self.database_instance = "scenario"
            def self.reset = ""

            def self.build(database_url:, warmup_runs:, runs:)
              [database_url, warmup_runs, runs]
            end
          end

        Scenario.stub(:definitions, [scenario]) do
          scenario =
            Runner
              .classic
              .instance_variable_get(:@scenarios)
              .fetch("scenario")
              .build
              .call("postgres://example", 2)

          assert_equal(["postgres://example", 2, 50], scenario)
        end
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

      def test_reset_en57_truncates_event_and_tag_tables
        assert_equal(
          "TRUNCATE en57.tags, en57.events RESTART IDENTITY CASCADE",
          Scenario::RESET_EN57,
        )
      end

      def test_reset_res_truncates_event_store_tables
        assert_equal(
          "TRUNCATE event_store_events, event_store_events_in_streams " \
            "RESTART IDENTITY CASCADE",
          Scenario::RESET_RES,
        )
      end

      def test_scenario_define_defaults_reset_to_en57_truncate
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(database_instance: "reset-default", name: "Reset")

        assert_equal(Scenario::RESET_EN57, scenario_class.reset)
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_scenario_define_accepts_custom_reset
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(
            database_instance: "reset-custom",
            name: "Reset",
            reset: "TRUNCATE custom",
          )

        assert_equal("TRUNCATE custom", scenario_class.reset)
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def test_seeded_scenario_reset_reloads_seed_after_truncate
        seeded =
          Scenario.definitions.find do
            it.database_instance ==
              "concurrent-append-non-conflicting-tags-seeded"
          end

        assert(seeded.reset.start_with?(Scenario::RESET_EN57))
        assert_includes(seeded.reset, "INSERT INTO en57.events")
      end

      def test_res_scenarios_reset_with_res_truncate
        res_scenarios =
          Scenario.definitions.select do
            it.database_instance.start_with?("res-")
          end

        refute_empty(res_scenarios)
        res_scenarios.each do |scenario|
          assert_equal(Scenario::RESET_RES, scenario.reset)
        end
      end

      def test_scenario_with_overrides_reset
        original_definitions = Scenario.definitions.dup
        scenario_class =
          Scenario.define(database_instance: "reset-base", name: "Base")
        copy = scenario_class.with(database_instance: "reset-copy", reset: "X")

        assert_equal(Scenario::RESET_EN57, scenario_class.reset)
        assert_equal("X", copy.reset)
      ensure
        Scenario.definitions.replace(original_definitions)
      end

      def fake_pg_connection
        Class
          .new do
            attr_reader :urls, :statements, :closed

            def initialize
              @urls = []
              @statements = []
              @closed = 0
            end

            def connect(url)
              @urls << url
              self
            end

            def exec(sql) = @statements << sql
            def close = @closed += 1
          end
          .new
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
