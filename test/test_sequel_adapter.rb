# frozen_string_literal: true

require "test_helper"

module En57
  class TestSequelAdapter < Minitest::Test
    cover SequelAdapter

    def test_with_connection_synchronizes_and_yields_connection
      with_mock_adapter do |database, connection, adapter|
        database.expect(:synchronize, :selected) do |&block|
          block.call(connection)
        end
        connection.expect(:exec, :selected, ["SELECT 1"])

        assert_equal(
          :selected,
          adapter.with_connection { |conn| conn.exec("SELECT 1") },
        )
      end
    end

    def test_with_serializable_transaction_synchronizes_inside_transaction
      with_mock_adapter do |database, connection, adapter|
        database.expect(:transaction, :committed) do |options, &block|
          assert_equal({ isolation: :serializable }, options)
          block.call
        end
        database.expect(:synchronize, :written) do |&block|
          block.call(connection)
        end
        connection.expect(
          :exec_params,
          :written,
          ["SELECT en57.append_events()", []],
        )

        assert_equal(
          :committed,
          adapter.with_serializable_transaction do |conn|
            assert_equal(
              :written,
              conn.exec_params("SELECT en57.append_events()", []),
            )
          end,
        )
      end
    end

    def test_with_serializable_transaction_unwraps_pg_errors
      assert_raises(PG::RaiseException) do
        with_mock_adapter do |database, _connection, adapter|
          database.expect(:transaction, nil) { |options, &block| block.call }
          database.expect(:synchronize, nil) do
            raise sequel_error(PG::RaiseException.new("boom"))
          end

          adapter.with_serializable_transaction { flunk "not yielded" }
        end
      end
    end

    def test_with_serializable_transaction_unwraps_pg_error_subclasses
      assert_raises(PG::TRSerializationFailure) do
        with_mock_adapter do |database, _connection, adapter|
          database.expect(:transaction, nil) { |options, &block| block.call }
          database.expect(:synchronize, nil) do
            raise sequel_error(PG::TRSerializationFailure.new("boom"))
          end

          adapter.with_serializable_transaction { flunk "not yielded" }
        end
      end
    end

    def test_serialization_error_returns_pg_serialization_failure
      with_mock_adapter do |_database, _connection, adapter|
        assert_same PG::TRSerializationFailure, adapter.serialization_error
      end
    end

    def test_with_transaction_synchronizes_inside_transaction
      with_mock_adapter do |database, connection, adapter|
        database.expect(:transaction, :committed) { |&block| block.call }
        database.expect(:synchronize, :written) do |&block|
          block.call(connection)
        end
        connection.expect(
          :exec_params,
          :written,
          ["SELECT en57.append_events()", []],
        )

        assert_equal(
          :committed,
          adapter.with_transaction do |conn|
            assert_equal(
              :written,
              conn.exec_params("SELECT en57.append_events()", []),
            )
          end,
        )
      end
    end

    def test_with_transaction_unwraps_pg_errors
      assert_raises(PG::RaiseException) do
        with_mock_adapter do |database, _connection, adapter|
          database.expect(:transaction, nil) { |&block| block.call }
          database.expect(:synchronize, nil) do
            raise sequel_error(PG::RaiseException.new("boom"))
          end

          adapter.with_transaction { flunk "not yielded" }
        end
      end
    end

    private

    def sequel_error(pg_error)
      sequel_error = Sequel::DatabaseError.new("wrapped")
      sequel_error.wrapped_exception = pg_error
      sequel_error
    end

    def with_mock_adapter
      database = Minitest::Mock.new
      connection = Minitest::Mock.new

      yield database, connection, SequelAdapter.new(database)
    ensure
      database.verify
      connection.verify
    end
  end
end
