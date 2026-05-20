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
                verified: true,
              ),
            ],
          )

        assert_equal(<<~TABLE.chomp, output)
          +----------+------+--------------+---------+---------+---------+---------+
          | Scenario | Runs | Mean latency | Stddev  | Min     | Max     | Median  |
          +----------+------+--------------+---------+---------+---------+---------+
          | scenario |   50 |      1.23 ms | 0.45 ms | 1.00 ms | 2.00 ms | 1.50 ms |
          +----------+------+--------------+---------+---------+---------+---------+
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
                verified: false,
              ),
            ],
          ),
        )
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
