# frozen_string_literal: true

require "test_helper"

module En57
  class TestActiveRecordAdapter < Minitest::Test
    cover ActiveRecordAdapter

    def test_with_connection_checks_out_connection_and_yields_raw_connection
      with_mock_adapter do |pool, connection, raw_connection, adapter|
        pool.expect(:with_connection, :selected) do |&block|
          block.call(connection)
          true
        end
        connection.expect(:raw_connection, raw_connection)
        raw_connection.expect(:exec, :selected, ["SELECT 1"])

        assert_equal :selected,
                     adapter.with_connection { |conn| conn.exec("SELECT 1") }
      end
    end

    def test_with_serializable_transaction_wraps_block_in_transaction
      with_mock_adapter do |pool, connection, raw_connection, adapter|
        pool.expect(:with_connection, :committed) do |&block|
          block.call(connection)
          true
        end
        connection.expect(:transaction, :committed) do |options, &block|
          assert_equal({ isolation: :serializable }, options)
          block.call
          true
        end
        connection.expect(:raw_connection, raw_connection)
        raw_connection.expect(
          :exec_params,
          :written,
          ["SELECT en57.append_events()", []],
        )

        assert_equal(
          :committed,
          adapter.with_serializable_transaction do |conn|
            assert_equal :written,
                         conn.exec_params("SELECT en57.append_events()", [])
          end,
        )
      end
    end

    def test_serialization_error_returns_active_record_serialization_failure
      with_mock_adapter do |_pool, _connection, _raw_connection, adapter|
        assert_same ActiveRecord::SerializationFailure,
                    adapter.serialization_error
      end
    end

    def test_with_serializable_transaction_reraises_block_errors
      error = RuntimeError.new("boom")

      raised =
        assert_raises(RuntimeError) do
          with_mock_adapter do |pool, connection, raw_connection, adapter|
            pool.expect(:with_connection, nil) do |&block|
              block.call(connection)
              true
            end
            connection.expect(:transaction, nil) do |options, &block|
              assert_equal({ isolation: :serializable }, options)
              block.call
              true
            end
            connection.expect(:raw_connection, raw_connection)
            raw_connection.expect(:exec_params, nil) do |sql, params|
              assert_equal "SELECT en57.append_events()", sql
              assert_equal [], params
              raise error
            end

            adapter.with_serializable_transaction do |conn|
              conn.exec_params("SELECT en57.append_events()", [])
            end
          end
        end

      assert_same error, raised
    end

    def test_with_transaction_wraps_block_in_transaction
      with_mock_adapter do |pool, connection, raw_connection, adapter|
        pool.expect(:with_connection, :committed) do |&block|
          block.call(connection)
          true
        end
        connection.expect(:transaction, :committed) do |&block|
          block.call
          true
        end
        connection.expect(:raw_connection, raw_connection)
        raw_connection.expect(
          :exec_params,
          :written,
          ["SELECT en57.append_events()", []],
        )

        assert_equal(
          :committed,
          adapter.with_transaction do |conn|
            assert_equal :written,
                         conn.exec_params("SELECT en57.append_events()", [])
          end,
        )
      end
    end

    def test_with_transaction_reraises_block_errors
      error = RuntimeError.new("boom")

      raised =
        assert_raises(RuntimeError) do
          with_mock_adapter do |pool, connection, raw_connection, adapter|
            pool.expect(:with_connection, nil) do |&block|
              block.call(connection)
              true
            end
            connection.expect(:transaction, nil) do |&block|
              block.call
              true
            end
            connection.expect(:raw_connection, raw_connection)
            raw_connection.expect(:exec_params, nil) do |sql, params|
              assert_equal "SELECT en57.append_events()", sql
              assert_equal [], params
              raise error
            end

            adapter.with_transaction do |conn|
              conn.exec_params("SELECT en57.append_events()", [])
            end
          end
        end

      assert_same error, raised
    end

    private

    def with_mock_adapter
      pool = Minitest::Mock.new
      connection = Minitest::Mock.new
      raw_connection = Minitest::Mock.new

      yield pool, connection, raw_connection, ActiveRecordAdapter.new(pool)
    ensure
      pool.verify
      connection.verify
      raw_connection.verify
    end
  end
end
