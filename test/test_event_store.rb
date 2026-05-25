# frozen_string_literal: true

require "test_helper"

module En57
  class TestEventStore < Minitest::Test
    cover EventStore

    def test_append_event
      event = Event.new(type: "CreditsToppedUp")

      with_repository do |repository|
        repository.expect(
          :append,
          Success.new(position: 1),
          [[event]],
          fail_if: Query.all,
        )

        EventStore.new(repository).append([event])
      end
    end

    def test_read_returns_scope_for_query_all
      event = Event.new(type: "CreditsToppedUp")

      with_repository do |repository|
        repository.expect(:read, [[event, 1]], [Query.all])

        result = EventStore.new(repository).read

        assert_instance_of(Scope, result)
        assert_equal([event], result.each.to_a)
      end
    end

    def test_returns_success_from_append
      event = Event.new(type: "CreditsToppedUp")

      with_repository do |repository|
        repository.expect(
          :append,
          Success.new(position: 1),
          [[event]],
          fail_if: Query.all,
        )

        assert_equal(
          Success.new(position: 1),
          EventStore.new(repository).append([event]),
        )
      end
    end

    def test_append_accepts_scope_for_fail_if
      event = Event.new(type: "CreditsToppedUp")

      with_repository do |repository|
        event_store = EventStore.new(repository)
        fail_if = event_store.read.with_tag("order_id:123")
        repository.expect(
          :append,
          Success.new(position: 1),
          [[event]],
          fail_if: fail_if.to_query,
        )

        event_store.append([event], fail_if:)
      end
    end

    private

    def with_repository
      repository = Minitest::Mock.new
      yield repository
      repository.verify
    end
  end
end
