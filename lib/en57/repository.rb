# frozen_string_literal: true

require "pg"

module En57
  class Repository
    def initialize(adapter, serializer = En57.configuration.serializer)
      @adapter = adapter
      @serializer = serializer
      @record_encoder = PG::TextEncoder::Record.new
      @array_encoder = PG::TextEncoder::Array.new
      @array_decoder = PG::TextDecoder::Array.new
    end

    def append(events, fail_if:)
      return Success.new(position: nil) if events.empty?

      event_records =
        events.map do |event|
          serialized, description = @serializer.dump(event.data)
          @record_encoder.encode(
            [
              event.id,
              event.type,
              (serialized unless event.data.empty?),
              description,
              @array_encoder.encode(event.tags),
            ],
          )
        end
      append_condition = {}
      fail_if_events_match = fail_if.encoded_criteria
      append_condition[
        :fail_if_events_match
      ] = fail_if_events_match unless fail_if_events_match.empty?

      statement =
        "SELECT status, position, conflicting_events FROM en57.append_events($1::en57.event[], $2::jsonb)"
      params = [
        @array_encoder.encode(event_records),
        JSON.generate(append_condition),
      ]

      attempts_remaining = En57.configuration.append_retries
      begin
        row =
          if fail_if_events_match.empty?
            @adapter.with_transaction do |connection|
              connection.exec_params(statement, params)
            end
          else
            @adapter.with_serializable_transaction do |connection|
              connection.exec_params(statement, params)
            end
          end

        case row.first.fetch("status")
        when "success"
          Success.new(
            position: row.first.fetch("position").then { Integer(it) },
          )
        when "append_condition_violated"
          Failure.new(
            position: row.first.fetch("position").then { Integer(it) },
            conflicting_events:
              JSON
                .parse(row.first.fetch("conflicting_events"))
                .map { deserialize_event(it) },
          )
        end
      rescue @adapter.serialization_error
        if attempts_remaining.positive?
          attempts_remaining -= 1
          retry
        end

        raise AppendRetriesExhausted
      end
    end

    def read(query)
      criteria = query.encoded_criteria.map { |item| JSON.generate(item) }

      @adapter
        .with_connection do |connection|
          connection.exec_params(
            "SELECT position, id, type, data, meta, tags FROM en57.read_events($1::jsonb[])",
            [@array_encoder.encode(criteria)],
          )
        end
        .map do |row|
          [
            deserialize_event(row),
            Integer(row.fetch("position")),
          ]
        end
    end

    private

    def json_string(value)
      value.instance_of?(String) ? value : JSON.generate(value)
    end

    def deserialize_event(row)
      Event.new(
        id: row.fetch("id"),
        type: row.fetch("type"),
        data:
          @serializer.load(
            json_string(row.fetch("data")),
            row.fetch("meta").then { json_string(it) if it },
          ),
        tags:
          row.fetch("tags").then do |tags|
            tags.instance_of?(Array) ? tags : @array_decoder.decode(tags)
          end,
      )
    end
  end
end
