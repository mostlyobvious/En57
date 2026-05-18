# frozen_string_literal: true

require "test_helper"

module En57
  class TestSuccess < Minitest::Test
    cover Success

    def test_carries_position
      result = Success.new(position: 42)

      assert(result.success?)
      refute(result.failure?)
      assert_equal(42, result.position)
    end
  end

  class TestFailure < Minitest::Test
    cover Failure

    def test_carries_position_and_conflicting_events
      conflict = Event.new(type: "OrderPlaced")
      result = Failure.new(position: 7, conflicting_events: [conflict])

      assert(result.failure?)
      refute(result.success?)
      assert_equal(7, result.position)
      assert_equal([conflict], result.conflicting_events)
    end
  end
end
