# frozen_string_literal: true

require "test_helper"

module En57
  class TestResult < Minitest::Test
    cover Result

    def test_success_carries_position
      result = Result.success(position: 42)

      assert(result.success?)
      refute(result.failure?)
      assert_equal(42, result.position)
    end

    def test_failure_carries_position_and_conflicting_events
      conflict = Event.new(type: "OrderPlaced")
      result = Result.failure(position: 7, conflicting_events: [conflict])

      assert(result.failure?)
      refute(result.success?)
      assert_equal(7, result.position)
      assert_equal([conflict], result.conflicting_events)
    end
  end
end
