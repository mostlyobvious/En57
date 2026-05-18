# frozen_string_literal: true

require "test_helper"

module En57
  class TestRepository < Minitest::Test
    cover Repository

    def test_append_wraps_write_in_serializable_transaction
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
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(
          :exec_params,
          [{ "position" => "2", "conflicting_events" => "[]" }],
          [
            "SELECT position, conflicting_events FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [expected_events, "{}"],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        result =
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

        assert_equal(Success.new(position: 2), result)
      end
    end

    def test_append_persists_empty_event_data_as_null
      expected_events =
        array_encoder.encode(
          [record_encoder.encode([ids[0], "OrderPlaced", nil, nil, "{}"])],
        )
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(
          :exec_params,
          [{ "position" => "1", "conflicting_events" => "[]" }],
          [
            "SELECT position, conflicting_events FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [expected_events, "{}"],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        result =
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append(
            [Event.new(id: ids[0], type: "OrderPlaced")],
            fail_if: Query.all,
          )

        assert_equal(Success.new(position: 1), result)
      end
    end

    def test_append_passes_fail_if_and_after_conditions
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(
          :exec_params,
          [{ "position" => nil, "conflicting_events" => "[]" }],
          [
            "SELECT position, conflicting_events FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [
              array_encoder.encode([]),
              '{"fail_if_events_match":[{"types":["OrderPlaced"],"after":42}]}',
            ],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        result =
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

        assert_equal(Success.new(position: nil), result)
      end
    end

    def test_append_rolls_back_transaction_on_pg_failure
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(:exec, nil, ["ROLLBACK"])
        connection.expect(:exec_params, nil) do |sql, params|
          assert_equal(
            "SELECT position, conflicting_events FROM en57.append_events($1::en57.event[], $2::jsonb)",
            sql,
          )
          assert_equal([array_encoder.encode([]), "{}"], params)
          raise PG::Error, "boom"
        end

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
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(:exec, nil, ["ROLLBACK"])
        connection.expect(:exec_params, nil) { raise RuntimeError, "boom" }

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

    def test_append_returns_failure_when_condition_matches
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(
          :exec_params,
          [
            {
              "position" => "5",
              "conflicting_events" =>
                JSON.generate(
                  [
                    {
                      id: ids[2],
                      type: "OrderPlaced",
                      data: '{"amount":100}',
                      meta: '{"amount":{"k":"Symbol"}}',
                      tags: ["order_id:123"],
                    },
                    {
                      id: ids[3],
                      type: "OrderPlaced",
                      data: nil,
                      meta: nil,
                      tags: [],
                    },
                  ],
                ),
            },
          ],
          [
            "SELECT position, conflicting_events FROM en57.append_events($1::en57.event[], $2::jsonb)",
            [
              array_encoder.encode([]),
              '{"fail_if_events_match":[{"types":["OrderPlaced"]}]}',
            ],
          ],
        )
        connection.expect(:exec, nil, ["COMMIT"])

        result =
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append(
            [],
            fail_if:
              Query.new(
                criteria: [
                  Query::Criteria.new(types: ["OrderPlaced"], tags: []),
                ],
              ),
          )

        assert_equal(
          Failure.new(
            position: 5,
            conflicting_events: [
              Event.new(
                id: ids[2],
                type: "OrderPlaced",
                data: {
                  amount: 100,
                },
                tags: ["order_id:123"],
              ),
              Event.new(id: ids[3], type: "OrderPlaced", data: {}, tags: []),
            ],
          ),
          result,
        )
      end
    end

    def test_append_returns_failure_on_serialization_failure
      with_connection do |connection|
        connection.expect(:exec, nil, ["BEGIN ISOLATION LEVEL SERIALIZABLE"])
        connection.expect(:exec, nil, ["ROLLBACK"])
        connection.expect(:exec_params, nil) do
          raise PG::TRSerializationFailure.new
        end

        result =
          Repository.new(
            PgAdapter.for_connection(connection),
            JsonSerializer.new,
          ).append([], fail_if: Query.all)

        assert_equal(Failure.new(position: nil, conflicting_events: []), result)
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
  end
end
