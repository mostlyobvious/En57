# frozen_string_literal: true

require "test_helper"

module En57
  class TestFactories < IntegrationTest
    def test_for_pg_round_trips_with_connection_uri
      assert_round_trip EventStore.for_pg(SERVER.url)
    end

    def test_for_pooled_pg_round_trips_with_default_max_connections
      assert_round_trip EventStore.for_pooled_pg(SERVER.url)
    end

    def test_for_pooled_pg_round_trips_with_custom_max_connections
      assert_round_trip EventStore.for_pooled_pg(SERVER.url, max_connections: 1)
    end

    def test_for_active_record_round_trips_with_default_model
      assert_round_trip EventStore.for_active_record
    end

    def test_for_active_record_round_trips_with_custom_model
      Object.stub_const(:DasModel, Class.new(ActiveRecord::Base)) do
        assert_round_trip(EventStore.for_active_record(DasModel))
      end
    end

    def test_for_sequel_round_trips_with_database
      assert_round_trip EventStore.for_sequel(SEQUEL_DB)
    end

    def test_event_store_does_not_conflict_with_public_schema_tables
      CONNECTION.exec("CREATE TABLE public.events (id integer PRIMARY KEY)")
      CONNECTION.exec("CREATE TABLE public.tags (id integer PRIMARY KEY)")

      assert_round_trip EventStore.for_pg(SERVER.url)
    ensure
      CONNECTION.exec("DROP TABLE IF EXISTS public.tags, public.events")
    end

    private

    def assert_round_trip(event_store)
      event = Event.new(type: "FactoryTested")

      assert_equal Success.new(position: 1), event_store.append([event])
      assert_equal [event], event_store.read.each.to_a
    end
  end
end
