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
    SERVER = PgEphemeral.start

    CONNECTION = PG.connect(SERVER.url)

    POOL_SIZE = 8

    PG_POOL = ConnectionPool.new(size: POOL_SIZE) { PG.connect(SERVER.url) }

    SEQUEL_DB =
      Sequel.connect(
        SERVER.url,
        preconnect: :concurrently,
        max_connections: POOL_SIZE,
      )

    AR_POOL = -> do
      ActiveRecord::Base.establish_connection("#{SERVER.url}&pool=#{POOL_SIZE}")
      ActiveRecord::Base.connection_pool
    end.call

    ADAPTERS = {
      pg: -> { PgAdapter.for_pool(PG_POOL) },
      sequel: -> { SequelAdapter.new(SEQUEL_DB) },
      active_record: -> { ActiveRecordAdapter.new(AR_POOL) },
    }

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
  end
end
