# frozen_string_literal: true

require "test_helper"

module En57
  class TestPgAdapter < Minitest::Test
    cover PgAdapter

    def test_with_connection_yields_connection
      with_mock_adapter do |connection, adapter|
        connection.expect(:exec, :selected, ["SELECT 1"])

        assert_equal :selected,
                     adapter.with_connection { |conn| conn.exec("SELECT 1") }
      end
    end

    def test_for_pool_uses_connection_pool
      connection = Object.new
      pool = Object.new
      pool.define_singleton_method(:with) { |&block| block.call(connection) }
      adapter = PgAdapter.for_pool(pool)

      assert_same connection, adapter.with_connection { |conn| conn }
    end

    def test_for_connection_synchronizes_access
      connection = Object.new
      adapter = PgAdapter.for_connection(connection)
      acquired = Queue.new
      release = Queue.new

      threads =
        2.times.map do
          Thread.new do
            adapter.with_connection do |conn|
              acquired << conn
              release.pop
            end
          end
        end

      assert_same connection, acquired.pop
      assert_raises(ThreadError) { acquired.pop(true) }

      release << true
      assert_same connection, acquired.pop

      release << true
      threads.each(&:value)
    end

    def test_with_serializable_transaction_commits_on_success
      with_mock_adapter do |connection, adapter|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(
          :exec_params,
          :written,
          ["SELECT en57.append_events()", []],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        assert_equal(
          :written,
          adapter.with_serializable_transaction do |conn|
            conn.exec_params("SELECT en57.append_events()", [])
          end,
        )
      end
    end

    def test_with_serializable_transaction_rolls_back_on_failure
      error = RuntimeError.new("boom")

      raised =
        assert_raises(RuntimeError) do
          with_mock_adapter do |connection, adapter|
            connection.expect(
              :exec,
              nil,
              ["BEGIN ISOLATION LEVEL SERIALIZABLE"],
            )
            connection.expect(:exec_params, nil) do |sql, params|
              assert_equal "SELECT en57.append_events()", sql
              assert_equal [], params
              raise error
            end
            connection.expect(:exec, nil, ["ROLLBACK"])

            adapter.with_serializable_transaction do |conn|
              conn.exec_params("SELECT en57.append_events()", [])
            end
          end
        end

      assert_same error, raised
    end

    private

    def with_mock_adapter
      connection = Minitest::Mock.new

      yield connection, PgAdapter.for_connection(connection)
    ensure
      connection.verify
    end
  end
end
