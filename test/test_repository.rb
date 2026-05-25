# frozen_string_literal: true

require "test_helper"

module En57
  class TestRepository < Minitest::Test
    cover Repository

    def test_append_without_fail_if_uses_plain_transaction
      expected_events =
        array_encoder.encode(
          [
            record_encoder.encode(
              [
                ids[0],
                "CreditsToppedUp",
                '{"amount":100}',
                '{"amount":{"k":"Symbol"}}',
                "{order_id:123}",
              ],
            ),
            record_encoder.encode(
              [
                ids[1],
                "CreditsToppedUp",
                '{"amount":50}',
                '{"amount":{"k":"Symbol"}}',
                "{order_id:234}",
              ],
            ),
          ],
        )
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN"])
        connection.expect(
          :exec_params,
          success_result,
          [
            "SELECT status FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [expected_events, "{}"],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        Repository.new(
          PgAdapter.for_connection(connection),
          JsonSerializer.new,
        ).append(
          [
            Event.new(
              id: ids[0],
              type: "CreditsToppedUp",
              data: {
                amount: 100,
              },
              tags: ["order_id:123"],
            ),
            Event.new(
              id: ids[1],
              type: "CreditsToppedUp",
              data: {
                amount: 50,
              },
              tags: ["order_id:234"],
            ),
          ],
          fail_if: Query.all,
        )
      end
    end

    def test_append_persists_empty_event_data_as_null
      expected_events =
        array_encoder.encode(
          [record_encoder.encode([ids[0], "OrderPlaced", nil, nil, "{}"])],
        )
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN"])
        connection.expect(
          :exec_params,
          success_result,
          [
            "SELECT status FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [expected_events, "{}"],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        Repository.new(
          PgAdapter.for_connection(connection),
          JsonSerializer.new,
        ).append(
          [Event.new(id: ids[0], type: "OrderPlaced")],
          fail_if: Query.all,
        )
      end
    end

    def test_append_passes_fail_if_and_after_conditions
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(
          :exec_params,
          success_result,
          [
            "SELECT status FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [
              array_encoder.encode([]),
              '{"fail_if_events_match":[{"types":["OrderPlaced"],"after":42}]}',
            ],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        Repository.new(
          PgAdapter.for_connection(connection),
          JsonSerializer.new,
        ).append(
          [],
          fail_if:
            Query.new(
              criteria: [
                Query::Criteria.new(
                  types: ["OrderPlaced"],
                  tags: [],
                  after: 42,
                ),
              ],
            ),
        )
      end
    end

    def test_append_rolls_back_transaction_on_pg_failure
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN"])
        connection.expect(:exec_params, nil) do |sql, params|
          assert_equal(
            "SELECT status FROM en57.append_events($1::en57.event[], $2::jsonb)",
            sql,
          )
          assert_equal([array_encoder.encode([]), "{}"], params)
          raise PG::Error, "boom"
        end
        connection.expect(:exec, nil, ["ROLLBACK"])

        assert_raises(PG::Error) do
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append([], fail_if: Query.all)
        end
      end
    end

    def test_append_rolls_back_transaction_on_failure
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN"])
        connection.expect(:exec_params, nil) { raise RuntimeError, "boom" }
        connection.expect(:exec, nil, ["ROLLBACK"])

        assert_raises(RuntimeError) do
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append([], fail_if: Query.all)
        end
      end
    end

    def test_read_events_with_tags
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "CreditsToppedUp",
              "data" => '{"amount":100}',
              "meta" => nil,
              "tags" => "{order_id:123}",
            },
            {
              "position" => "2",
              "id" => ids[1],
              "type" => "CreditsToppedUp",
              "data" => '{"amount":50}',
              "meta" => nil,
              "tags" => "{order_id:234}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode([])],
          ],
        )

        assert_equal(
          [
            [
              Event.new(
                id: ids[0],
                type: "CreditsToppedUp",
                data: {
                  "amount" => 100,
                },
                tags: ["order_id:123"],
              ),
              1,
            ],
            [
              Event.new(
                id: ids[1],
                type: "CreditsToppedUp",
                data: {
                  "amount" => 50,
                },
                tags: ["order_id:234"],
              ),
              2,
            ],
          ],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(Query.all),
        )
      end
    end

    def test_read_events_with_metadata_restores_types
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "CreditsToppedUp",
              "data" => '{"amount":100}',
              "meta" => '{"amount":{"k":"Symbol"}}',
              "tags" => "{}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode([])],
          ],
        )

        assert_equal(
          [
            [
              Event.new(
                id: ids[0],
                type: "CreditsToppedUp",
                data: {
                  amount: 100,
                },
              ),
              1,
            ],
          ],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(Query.all),
        )
      end
    end

    def test_read_events_with_null_data_returns_empty_hash
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "OrderPlaced",
              "data" => nil,
              "meta" => nil,
              "tags" => "{}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode([])],
          ],
        )

        assert_equal(
          [[Event.new(id: ids[0], type: "OrderPlaced", data: {}), 1]],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(Query.all),
        )
      end
    end

    def test_read_events_filtered_by_tags
      query =
        Query.new(
          criteria: [Query::Criteria.new(types: [], tags: ["order_id:123"])],
        )
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "CreditsToppedUp",
              "data" => '{"amount":100}',
              "meta" => nil,
              "tags" => "{order_id:123}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode(['{"tags":["order_id:123"]}'])],
          ],
        )

        assert_equal(
          [
            [
              Event.new(
                id: ids[0],
                type: "CreditsToppedUp",
                data: {
                  "amount" => 100,
                },
                tags: ["order_id:123"],
              ),
              1,
            ],
          ],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(query),
        )
      end
    end

    def test_read_events_with_wildcard_query_item
      query = Query.new(criteria: [Query::Criteria.new(types: [], tags: [])])
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "CreditsToppedUp",
              "data" => '{"amount":100}',
              "meta" => nil,
              "tags" => "{order_id:123}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode(["{}"])],
          ],
        )

        assert_equal(
          [
            [
              Event.new(
                id: ids[0],
                type: "CreditsToppedUp",
                data: {
                  "amount" => 100,
                },
                tags: ["order_id:123"],
              ),
              1,
            ],
          ],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(query),
        )
      end
    end

    def test_read_events_with_or_tag_predicates
      query =
        Query.new(
          criteria: [
            Query::Criteria.new(types: [], tags: ["order_id:123"]),
            Query::Criteria.new(types: [], tags: ["order_id:456"]),
          ],
        )
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "CreditsToppedUp",
              "data" => '{"amount":100}',
              "meta" => nil,
              "tags" => "{order_id:123}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [
              array_encoder.encode(
                %w[{"tags":["order_id:123"]} {"tags":["order_id:456"]}],
              ),
            ],
          ],
        )

        assert_equal(
          [
            [
              Event.new(
                id: ids[0],
                type: "CreditsToppedUp",
                data: {
                  "amount" => 100,
                },
                tags: ["order_id:123"],
              ),
              1,
            ],
          ],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(query),
        )
      end
    end

    def test_read_events_filtered_by_after
      query =
        Query.new(
          criteria: [Query::Criteria.new(types: [], tags: [], after: 42)],
        )
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode(['{"after":42}'])],
          ],
        )

        assert_equal(
          [],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(query),
        )
      end
    end

    def test_read_events_filtered_by_type
      query =
        Query.new(
          criteria: [Query::Criteria.new(types: ["OrderPlaced"], tags: [])],
        )
      with_connection do |connection|
        connection.expect(
          :exec_params,
          [
            {
              "position" => "1",
              "id" => ids[0],
              "type" => "OrderPlaced",
              "data" => '{"amount":100}',
              "meta" => nil,
              "tags" => "{}",
            },
          ],
          [
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [array_encoder.encode(['{"types":["OrderPlaced"]}'])],
          ],
        )

        assert_equal(
          [
            [
              Event.new(
                id: ids[0],
                type: "OrderPlaced",
                data: {
                  "amount" => 100,
                },
                tags: [],
              ),
              1,
            ],
          ],
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).read(query),
        )
      end
    end

    def test_append_returns_failure_when_sql_status_is_append_condition_violated
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(:exec_params, failure_result, append_args)
        connection.expect(:exec, nil, ["COMMIT"])

        assert_equal(
          Failure.new,
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append([], fail_if: fail_if_with_criteria),
        )
      end
    end

    def test_append_retries_on_serialization_error_and_succeeds
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(:exec_params, nil) do
          raise PG::TRSerializationFailure.new
        end
        connection.expect(:exec, nil, ["ROLLBACK"])
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(:exec_params, success_result, append_args)
        connection.expect(:exec, nil, ["COMMIT"])

        assert_equal(
          Success.new,
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append([], fail_if: fail_if_with_criteria),
        )
      end
    end

    def test_append_raises_serialization_error_after_four_attempts
      attempts = 0

      with_connection do |connection|
        4.times do
          connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
          connection.expect(:exec_params, nil) do
            attempts += 1
            raise PG::TRSerializationFailure.new
          end
          connection.expect(:exec, nil, ["ROLLBACK"])
        end

        assert_raises(AppendRetriesExhausted) do
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append([], fail_if: fail_if_with_criteria)
        end
        assert_equal(4, attempts)
      end
    end

    private

    def ids = @ids ||= Hash.new { |h, k| h[k] = SecureRandom.uuid_v7 }

    def with_connection
      connection = Minitest::Mock.new

      yield connection
      connection.verify
    end

    def array_encoder = @array_encoder ||= PG::TextEncoder::Array.new

    def record_encoder = @record_encoder ||= PG::TextEncoder::Record.new

    def success_result = [{ "status" => "success" }]

    def failure_result = [{ "status" => "append_condition_violated" }]

    def append_args
      [
        "SELECT status FROM en57.append_events($1::en57.event[], $2::jsonb)",
        [
          array_encoder.encode([]),
          '{"fail_if_events_match":[{"types":["OrderPlaced"]}]}',
        ],
      ]
    end

    def fail_if_with_criteria
      Query.new(
        criteria: [Query::Criteria.new(types: ["OrderPlaced"], tags: [])],
      )
    end
  end
end
