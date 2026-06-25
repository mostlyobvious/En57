# frozen_string_literal: true

require "test_helper"

module En57
  class TestEphemeralDatabase < Minitest::Test
    cover "En57::EphemeralDatabase*"

    def test_clones_from_template_yields_url_then_drops_and_closes
      admin = recording_connection
      urls = []
      yielded = nil
      connect = ->(url) do
        urls << url
        admin
      end

      result =
        PG.stub(:connect, connect) do
          EphemeralDatabase.with(template: "golden_x") do |database_url|
            yielded = database_url
            "block-result"
          end
        end

      assert_equal([EphemeralDatabase::ADMIN_URL], urls)
      assert_match(%r{\Apostgres:///en57\.\h{16}\z}, yielded)

      name = yielded.delete_prefix("postgres:///")
      assert_equal(
        [
          %(CREATE DATABASE "#{name}" TEMPLATE "golden_x"),
          %(DROP DATABASE IF EXISTS "#{name}" WITH (FORCE)),
        ],
        admin.statements,
      )
      assert_equal(1, admin.closed)
      assert_equal("block-result", result)
    end

    def test_without_template_creates_a_plain_database
      admin = recording_connection
      yielded = nil

      PG.stub(:connect, ->(_url) { admin }) do
        EphemeralDatabase.with { |database_url| yielded = database_url }
      end

      name = yielded.delete_prefix("postgres:///")
      assert_equal(%(CREATE DATABASE "#{name}"), admin.statements.fetch(0))
    end

    def test_uses_the_given_prefix_for_the_database_name
      yielded = nil

      PG.stub(:connect, ->(_url) { recording_connection }) do
        EphemeralDatabase.with(prefix: "migrator") { |url| yielded = url }
      end

      assert_match(%r{\Apostgres:///migrator\.\h{16}\z}, yielded)
    end

    def test_drops_and_closes_even_when_the_block_raises
      admin = recording_connection
      boom = Class.new(StandardError)

      assert_raises(boom) do
        PG.stub(:connect, ->(_url) { admin }) do
          EphemeralDatabase.with(template: "golden_x") { raise boom }
        end
      end

      assert_equal(2, admin.statements.size)
      assert_match(
        /\ADROP DATABASE IF EXISTS .+ WITH \(FORCE\)\z/,
        admin.statements.fetch(1),
      )
      assert_equal(1, admin.closed)
    end

    def test_propagates_connection_errors_without_running_teardown
      boom = Class.new(StandardError)

      assert_raises(boom) do
        PG.stub(:connect, ->(_url) { raise boom }) do
          EphemeralDatabase.with(template: "golden_x") do
            flunk("must not yield")
          end
        end
      end
    end

    private

    def recording_connection
      Class
        .new do
          attr_reader :statements, :closed

          def initialize
            @statements = []
            @closed = 0
          end

          def exec(sql) = @statements << sql
          def close = @closed += 1
        end
        .new
    end
  end
end
