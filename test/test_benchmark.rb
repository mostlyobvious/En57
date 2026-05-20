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
                verified: true,
              ),
            ],
          )

        assert_equal(<<~TABLE.chomp, output)
          +----------+------+--------------+---------+
          | Scenario | Runs | Mean latency | Stddev  |
          +----------+------+--------------+---------+
          | scenario |   50 |      1.23 ms | 0.45 ms |
          +----------+------+--------------+---------+
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
                verified: false,
              ),
            ],
          ),
        )
      end

      def test_measurement_calculates_mean_and_stddev
        measurement = Measurement.from([0.1, 0.2, 0.3])

        assert_in_delta(0.2, measurement.mean)
        assert_in_delta(0.08165, measurement.stddev, 0.00001)
      end
    end
  end
end
