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
        "SELECT status FROM en57.append_events($1::en57.event[], $2::jsonb)"
      params = [
        @array_encoder.encode(event_records),
        JSON.generate(append_condition),
      ]

      attempts_remaining = 3
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
          Success.new
        when "append_condition_violated"
          Failure.new
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
            Event.new(
              id: row.fetch("id"),
              type: row.fetch("type"),
              data:
                @serializer.load(row.fetch("data") || "{}", row.fetch("meta")),
              tags: @array_decoder.decode(row.fetch("tags")),
            ),
            Integer(row.fetch("position")),
          ]
        end
    end
  end
end
