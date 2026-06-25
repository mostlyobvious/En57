# frozen_string_literal: true

require "test_helper"

module En57
  class TestMigrator < IntegrationTest
    def setup = nil
    def teardown = nil

    def test_status_reports_pending_schema_on_empty_database
      with_database do |url|
        assert_equal(
          Migrator::Status.new(
            current: :fresh,
            target: "0.1.0",
            state: :pending,
            method: :none,
            pending: [schema_path("0.1.0")],
            warning: nil,
          ),
          Migrator.new(url).status,
        )
      end
    end

    def test_migrate_applies_pending_schema_and_records_version
      with_database do |url|
        migrator = Migrator.new(url)

        migrator.migrate!
        migrator.migrate!

        assert_equal(
          Migrator::Status.new(
            current: "0.1.0",
            target: "0.1.0",
            state: :up_to_date,
            method: :version_table,
            pending: [],
            warning: nil,
          ),
          migrator.status,
        )
      end
    end

    def test_migrate_installs_schema_used_by_event_store
      with_database do |url|
        Migrator.new(url).migrate!
        event = Event.new(type: "Migrated")
        connection = PG.connect(url)
        event_store =
          EventStore.new(
            Repository.new(
              PgAdapter.for_connection(connection),
              JsonSerializer.new,
            ),
          )

        assert_equal Success.new(position: 1), event_store.append([event])
        assert_equal [event], event_store.read.each.to_a
      ensure
        connection&.close
      end
    end

    def test_migrate_leaves_partial_status_after_failure
      with_database do |url|
        connection = PG.connect(url)
        connection.exec("CREATE SCHEMA en57")
        connection.close

        assert_raises(PG::DuplicateSchema) { Migrator.new(url).migrate! }

        status = Migrator.new(url).status
        assert_equal :partial, status.current
        assert_equal :partial, status.state
        assert_match(
          /Previous En57 migration did not complete cleanly/,
          status.warning,
        )
      end
    end

    def test_migrate_rejects_partial_status
      with_database do |url|
        connection = PG.connect(url)
        connection.exec(<<~SQL)
          CREATE TABLE public.en57_schema_info (
            id integer PRIMARY KEY,
            schema_version varchar(20) NOT NULL,
            in_progress boolean NOT NULL DEFAULT false,
            started_at timestamp,
            applied_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
          )
        SQL
        connection.exec(<<~SQL)
          INSERT INTO public.en57_schema_info (id, schema_version, in_progress)
          VALUES (1, '0.1.0', true)
        SQL
        connection.close

        error =
          assert_raises(Migrator::MigrationError) { Migrator.new(url).migrate! }
        assert_match(
          /Previous En57 migration did not complete cleanly/,
          error.message,
        )
      end
    end

    private

    def with_database(&block) =
      EphemeralDatabase.with(prefix: "en57-migrator", &block)

    def schema_path(version)
      File.expand_path("../db/schema/#{version}.sql", __dir__)
    end
  end
end
