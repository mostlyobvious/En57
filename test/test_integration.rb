# frozen_string_literal: true

require "test_helper"

module En57
  class TestIntegration < IntegrationTest
    ADAPTERS.each do |name, factory|
      define_method "test_#{name}_happy_path" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(
              id: ids[0],
              type: "CreditsToppedUp",
              data: {
                amount: 100,
              },
            ),
            Event.new(
              id: ids[1],
              type: "CreditsToppedUp",
              data: {
                amount: 50,
              },
            ),
          ]

          assert_equal(Success.new(position: 2), event_store.append(events))
          assert_equal(events, event_store.read.each.to_a)
        end
      end

      define_method "test_#{name}_read_with_position_yields_events_and_positions" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(id: ids[0], type: "OrderPlaced"),
            Event.new(id: ids[1], type: "PriceChanged"),
          ]

          assert_equal(Success.new(position: 2), event_store.append(events))
          assert_equal(
            events.map.with_index(1) { |event, position| [event, position] },
            event_store.read.each_with_position.to_a,
          )
        end
      end

      define_method "test_#{name}_append_with_fail_if_and_no_matches_appends_events" do
        with_event_store(factory) do |event_store|
          event = Event.new(id: ids[0], type: "OrderPlaced")
          assert_equal(
            Success.new(position: 1),
            event_store.append(
              [event],
              fail_if: event_store.read.of_type("PriceChanged"),
            ),
          )

          assert_equal([event], event_store.read.each.to_a)
        end
      end

      define_method "test_#{name}_append_with_fail_if_and_matches_returns_failure" do
        with_event_store(factory) do |event_store|
          existing_event = Event.new(id: ids[0], type: "OrderPlaced")
          assert_equal(
            Success.new(position: 1),
            event_store.append([existing_event]),
          )

          assert_equal(
            Failure.new(position: 1),
            event_store.append(
              [Event.new(id: ids[1], type: "ShipmentScheduled")],
              fail_if: event_store.read.of_type("OrderPlaced"),
            ),
          )

          assert_equal([existing_event], event_store.read.each.to_a)
        end
      end

      define_method "test_#{name}_append_with_after_ignores_matches_at_or_before_cutoff" do
        with_event_store(factory) do |event_store|
          existing_event = Event.new(id: ids[0], type: "OrderPlaced")
          assert_equal(
            Success.new(position: 1),
            event_store.append([existing_event]),
          )
          assert_equal(
            Success.new(position: 2),
            event_store.append(
              [Event.new(id: ids[1], type: "ShipmentScheduled")],
              fail_if: event_store.read.of_type("OrderPlaced").after(1),
            ),
          )

          assert_equal(
            [existing_event, Event.new(id: ids[1], type: "ShipmentScheduled")],
            event_store.read.each.to_a,
          )
        end
      end

      define_method "test_#{name}_append_with_after_returns_failure_if_match_is_after_cutoff" do
        with_event_store(factory) do |event_store|
          existing_event = Event.new(id: ids[0], type: "OrderPlaced")
          assert_equal(
            Success.new(position: 1),
            event_store.append([existing_event]),
          )

          assert_equal(
            Failure.new(position: 1),
            event_store.append(
              [Event.new(id: ids[1], type: "ShipmentScheduled")],
              fail_if: event_store.read.of_type("OrderPlaced").after(0),
            ),
          )

          assert_equal([existing_event], event_store.read.each.to_a)
        end
      end

      define_method "test_#{name}_append_with_duplicate_id_raises_unique_violation" do
        with_event_store(factory) do |event_store|
          existing_event = Event.new(id: ids[0], type: "OrderPlaced")
          assert_equal(
            Success.new(position: 1),
            event_store.append([existing_event]),
          )

          assert_raises(PG::UniqueViolation) do
            event_store.append(
              [Event.new(id: ids[0], type: "ShipmentScheduled")],
            )
          end

          assert_equal([existing_event], event_store.read.each.to_a)
        end
      end

      define_method "test_#{name}_tags_round_trip" do
        with_event_store(factory) do |event_store|
          event =
            Event.new(id: ids[0], type: "OrderPlaced", tags: ["order_id:123"])

          assert_equal(Success.new(position: 1), event_store.append([event]))
          assert_equal([event], event_store.read.each.to_a)
        end
      end

      define_method "test_#{name}_read_filters_after" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(id: ids[0], type: "OrderPlaced"),
            Event.new(id: ids[1], type: "PriceChanged"),
          ]

          assert_equal(Success.new(position: 2), event_store.append(events))
          assert_equal(events.drop(1), event_store.read.after(1).each.to_a)
        end
      end

      define_method "test_#{name}_read_filters_by_tags" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(
              id: ids[0],
              type: "OrderPlaced",
              tags: %w[order_id:123 tenant_id:acme],
            ),
            Event.new(
              id: ids[1],
              type: "OrderPlaced",
              tags: %w[order_id:456 tenant_id:acme],
            ),
          ]

          assert_equal(Success.new(position: 2), event_store.append(events))
          assert_equal(
            events.take(1),
            event_store
              .read
              .with_tag("order_id:123", "tenant_id:acme")
              .each
              .to_a,
          )
        end
      end

      define_method "test_#{name}_read_filters_by_type" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(id: ids[0], type: "OrderPlaced"),
            Event.new(id: ids[1], type: "PriceChanged"),
          ]

          assert_equal(Success.new(position: 2), event_store.append(events))
          assert_equal(
            events.take(1),
            event_store.read.of_type("OrderPlaced").each.to_a,
          )
        end
      end

      define_method "test_#{name}_read_filters_by_any_of_types" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(id: ids[0], type: "PriceChanged"),
            Event.new(id: ids[1], type: "OrderPlaced"),
            Event.new(id: ids[2], type: "OrderCancelled"),
          ]

          assert_equal(Success.new(position: 3), event_store.append(events))
          assert_equal(
            events.drop(1),
            event_store.read.of_type("OrderPlaced", "OrderCancelled").each.to_a,
          )
        end
      end

      define_method "test_#{name}_read_filters_by_type_and_tag_on_same_item" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(id: ids[0], type: "OrderPlaced", tags: ["order_id:123"]),
            Event.new(id: ids[1], type: "OrderPlaced", tags: ["order_id:456"]),
            Event.new(id: ids[2], type: "PriceChanged", tags: ["order_id:123"]),
          ]

          assert_equal(Success.new(position: 3), event_store.append(events))
          assert_equal(
            events.take(1),
            event_store
              .read
              .of_type("OrderPlaced")
              .with_tag("order_id:123")
              .each
              .to_a,
          )
        end
      end

      define_method "test_#{name}_read_or_combines_scopes_as_disjunction" do
        with_event_store(factory) do |event_store|
          events = [
            Event.new(id: ids[0], type: "OrderPlaced", tags: ["order_id:123"]),
            Event.new(id: ids[1], type: "OrderPlaced", tags: ["order_id:456"]),
            Event.new(id: ids[2], type: "PriceChanged", tags: ["order_id:999"]),
            Event.new(id: ids[3], type: "InventoryAdjusted", tags: ["sku:A1"]),
            Event.new(
              id: ids[4],
              type: "ShipmentScheduled",
              tags: ["order_id:123"],
            ),
          ]
          assert_equal(Success.new(position: 5), event_store.append(events))

          orders =
            event_store.read.of_type("OrderPlaced").with_tag("order_id:123")
          prices = event_store.read.of_type("PriceChanged")

          assert_equal(events.fetch_values(0, 2), (orders | prices).each.to_a)
        end
      end
    end

    private

    def ids = @ids ||= Hash.new { |h, k| h[k] = SecureRandom.uuid_v7 }

    def with_event_store(factory)
      yield(EventStore.new(Repository.new(factory.call, JsonSerializer.new)))
    end
  end
end
