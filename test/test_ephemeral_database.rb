# frozen_string_literal: true

require "test_helper"
require "en57/ephemeral_database"

module En57
  class TestEphemeralDatabase < Minitest::Test
    cover "En57::EphemeralDatabase*"

    def test_uses_admin_url_to_create_and_yield_database_url
      admin = recording_connection
      yielded = nil
      admin_url = "postgres://user:secret@127.0.0.1:55432/postgres"

      PG.stub(:connect, ->(url) { admin.tap { it.urls << url } }) do
        EphemeralDatabase.with(admin_url:, prefix: "migrator") do |database_url|
          yielded = database_url
        end
      end

      name = yielded.delete_prefix("postgres://user:secret@127.0.0.1:55432/")
      assert_match(/\Amigrator\.\h{16}\z/, name)
      assert_equal([admin_url], admin.urls)
      assert_equal(
        [
          %(CREATE DATABASE "#{name}"),
          %(DROP DATABASE IF EXISTS "#{name}" WITH (FORCE)),
        ],
        admin.statements,
      )
      assert_equal(1, admin.closed)
    end

    def test_admin_url_uses_database_url
      ENV["DATABASE_URL"] = "postgres://127.0.0.1:15432/postgres"

      assert_equal(
        "postgres://127.0.0.1:15432/postgres",
        EphemeralDatabase.admin_url,
      )
    ensure
      ENV.delete("DATABASE_URL")
    end

    def test_admin_url_uses_pg_env
      ENV.delete("DATABASE_URL")
      ENV["PGHOST"] = "/tmp/devenv/postgres"
      ENV["PGPORT"] = "55432"

      assert_equal(
        "postgres:///postgres?host=%2Ftmp%2Fdevenv%2Fpostgres&port=55432",
        EphemeralDatabase.admin_url,
      )
    ensure
      ENV.delete("PGHOST")
      ENV.delete("PGPORT")
    end

    def test_admin_url_uses_live_socket_port
      ENV.delete("DATABASE_URL")
      ENV["PGHOST"] = "/tmp/devenv/postgres"
      ENV["PGPORT"] = "5432"

      glob = ->(pattern) do
        assert_equal("/tmp/devenv/postgres/.s.PGSQL.*", pattern)
        %w[
          /tmp/devenv/postgres/.s.PGSQL.lock
          /tmp/devenv/postgres/.s.PGSQL.55432
        ]
      end

      Dir.stub(:glob, glob) do
        assert_equal(
          "postgres:///postgres?host=%2Ftmp%2Fdevenv%2Fpostgres&port=55432",
          EphemeralDatabase.admin_url,
        )
      end
    ensure
      ENV.delete("PGHOST")
      ENV.delete("PGPORT")
    end

    def test_admin_url_defaults_pg_env_port
      ENV.delete("DATABASE_URL")
      ENV["PGHOST"] = "/tmp/devenv/postgres"
      ENV.delete("PGPORT")

      assert_equal(
        "postgres:///postgres?host=%2Ftmp%2Fdevenv%2Fpostgres&port=5432",
        EphemeralDatabase.admin_url,
      )
    ensure
      ENV.delete("PGHOST")
    end

    def test_admin_url_defaults_to_bare_postgres_url
      ENV.delete("DATABASE_URL")
      ENV.delete("PGHOST")
      ENV.delete("PGPORT")

      assert_equal(EphemeralDatabase::ADMIN_URL, EphemeralDatabase.admin_url)
    end

    def test_defaults_to_bare_postgres_url
      ENV.delete("DATABASE_URL")
      ENV.delete("PGHOST")
      ENV.delete("PGPORT")
      admin = recording_connection
      yielded = nil

      PG.stub(:connect, ->(url) { admin.tap { it.urls << url } }) do
        EphemeralDatabase.with { |database_url| yielded = database_url }
      end

      assert_equal([EphemeralDatabase::ADMIN_URL], admin.urls)
      assert_match(%r{\Apostgres:///en57\.\h{16}\z}, yielded)
    end

    def test_preserves_admin_url_query_in_database_url
      admin = recording_connection
      yielded = nil

      PG.stub(:connect, ->(_url) { admin }) do
        EphemeralDatabase.with(
          admin_url:
            "postgres:///postgres?host=%2Ftmp%2Fdevenv%2Fpostgres&port=55432",
        ) { |database_url| yielded = database_url }
      end

      assert_match(
        %r{\Apostgres:///en57\.\h{16}\?host=%2Ftmp%2Fdevenv%2Fpostgres&port=55432\z},
        yielded,
      )
    end

    def test_uses_template_and_returns_block_result
      admin = recording_connection
      yielded = nil

      result =
        PG.stub(:connect, ->(_url) { admin }) do
          EphemeralDatabase.with(template: "golden_x") do |database_url|
            yielded = database_url
            "block-result"
          end
        end

      name = yielded.delete_prefix("postgres:///")
      assert_equal(
        [
          %(CREATE DATABASE "#{name}" TEMPLATE "golden_x"),
          %(DROP DATABASE IF EXISTS "#{name}" WITH (FORCE)),
        ],
        admin.statements,
      )
      assert_equal("block-result", result)
    end

    def test_drops_and_closes_when_block_raises
      admin = recording_connection
      boom = Class.new(StandardError)

      assert_raises(boom) do
        PG.stub(:connect, ->(_url) { admin }) do
          EphemeralDatabase.with { raise boom }
        end
      end

      assert_equal(2, admin.statements.size)
      assert_match(
        /\ADROP DATABASE IF EXISTS "en57\.\h{16}" WITH \(FORCE\)\z/,
        admin.statements.fetch(1),
      )
      assert_equal(1, admin.closed)
    end

    def test_propagates_connection_errors_without_teardown
      boom = Class.new(StandardError)

      assert_raises(boom) do
        PG.stub(:connect, ->(_url) { raise boom }) do
          EphemeralDatabase.with { flunk("must not yield") }
        end
      end
    end

    private

    def recording_connection
      Class
        .new do
          attr_reader :statements, :closed, :urls

          def initialize
            @statements = []
            @closed = 0
            @urls = []
          end

          def exec(sql) = @statements << sql
          def close = @closed += 1
        end
        .new
    end
  end
end
