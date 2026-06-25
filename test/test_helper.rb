# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "minitest/stub_const"
require "mutant/minitest/coverage"

# optional dependencies
require "sequel"
require "active_record"
require "connection_pool"

require "en57"
require "en57/ephemeral_database"

# test dependencies
require "securerandom"
require "concurrent-ruby"

module En57
  class IntegrationTest < Minitest::Test
    ADAPTER_NAMES = %i[pg sequel active_record]

    POOL_SIZE = 8

    attr_reader :database_url, :connection, :sequel_db

    def setup
      @admin = PG.connect(EphemeralDatabase::ADMIN_URL)
      @database_name = "en57.#{SecureRandom.hex(8)}"
      @admin.exec(
        "CREATE DATABASE #{PG::Connection.quote_ident(@database_name)} " \
          "TEMPLATE golden_en57",
      )
      @database_url = "postgres:///#{@database_name}"

      @connection = PG.connect(@database_url)
      @pg_pool =
        ConnectionPool.new(size: POOL_SIZE) { PG.connect(@database_url) }
      @sequel_db = Sequel.connect(@database_url, max_connections: POOL_SIZE)
      ActiveRecord::Base.establish_connection(
        "#{@database_url}?pool=#{POOL_SIZE}",
      )
      @ar_pool = ActiveRecord::Base.connection_pool
    end

    def teardown
      @ar_pool&.disconnect!
      @sequel_db&.disconnect
      @pg_pool&.shutdown(&:close)
      @connection&.close
      @admin&.exec(
        "DROP DATABASE IF EXISTS " \
          "#{PG::Connection.quote_ident(@database_name)} WITH (FORCE)",
      )
      @admin&.close
    end

    def adapter_factory(name)
      {
        pg: -> { PgAdapter.for_pool(@pg_pool) },
        sequel: -> { SequelAdapter.new(@sequel_db) },
        active_record: -> { ActiveRecordAdapter.new(@ar_pool) },
      }.fetch(name)
    end
  end
end
