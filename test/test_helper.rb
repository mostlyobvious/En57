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

    ADMIN = PG.connect(EphemeralDatabase::ADMIN_URL)
    DATABASE_NAME = "en57.#{SecureRandom.hex(8)}"
    ADMIN.exec(
      "CREATE DATABASE #{PG::Connection.quote_ident(DATABASE_NAME)} " \
        "TEMPLATE golden_en57",
    )
    DATABASE_URL = "postgres:///#{DATABASE_NAME}"

    CONNECTION = PG.connect(DATABASE_URL)
    PG_POOL = ConnectionPool.new(size: POOL_SIZE) { PG.connect(DATABASE_URL) }
    SEQUEL_DB = Sequel.connect(DATABASE_URL, max_connections: POOL_SIZE)
    AR_POOL = -> do
      ActiveRecord::Base.establish_connection(
        "#{DATABASE_URL}?pool=#{POOL_SIZE}",
      )
      ActiveRecord::Base.connection_pool
    end.call

    def database_url = DATABASE_URL
    def connection = CONNECTION
    def sequel_db = SEQUEL_DB

    def setup =
      CONNECTION.exec(
        "TRUNCATE TABLE en57.tags, en57.events RESTART IDENTITY CASCADE",
      )

    Minitest.after_run do
      AR_POOL.disconnect!
      SEQUEL_DB.disconnect
      PG_POOL.shutdown(&:close)
      CONNECTION.close
      ADMIN.exec(
        "DROP DATABASE IF EXISTS " \
          "#{PG::Connection.quote_ident(DATABASE_NAME)} WITH (FORCE)",
      )
      ADMIN.close
    end

    def adapter_factory(name)
      {
        pg: -> { PgAdapter.for_pool(PG_POOL) },
        sequel: -> { SequelAdapter.new(SEQUEL_DB) },
        active_record: -> { ActiveRecordAdapter.new(AR_POOL) },
      }.fetch(name)
    end
  end
end
