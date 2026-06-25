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

# test dependencies
require "securerandom"
require "concurrent-ruby"
require "pg_ephemeral"

module En57
  class IntegrationTest < Minitest::Test
    ADAPTER_NAMES = %i[pg sequel active_record]

    POOL_SIZE = 8

    SERVER = PgEphemeral.start

    DATABASE_URL = SERVER.url

    CONNECTION = PG.connect(DATABASE_URL)
    PG_POOL = ConnectionPool.new(size: POOL_SIZE) { PG.connect(DATABASE_URL) }
    SEQUEL_DB = Sequel.connect(DATABASE_URL, max_connections: POOL_SIZE)
    AR_POOL = -> do
      ActiveRecord::Base.establish_connection(
        "#{DATABASE_URL}&pool=#{POOL_SIZE}",
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
      SERVER.shutdown
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
