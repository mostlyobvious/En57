# frozen_string_literal: true

require "json"
require "date"
require "time"

module En57
  class JsonSerializer
    IDENTITY = lambda { it }
    Type = Data.define(:match, :name, :dump, :load)

    class Registry
      def initialize
        @types = []
        @by_name = {}
      end

      def register(type)
        @types << type
        @by_name[type.name] = type
      end

      def by_value(value) = @types.find { it.match === value }

      def by_name(name) = @by_name.fetch(name)
    end

    def initialize
      @key_types = Registry.new
      @value_types = Registry.new
      [
        symbol_type,
        date_type,
        time_type,
        binary_type,
        *optional_big_decimal_type,
      ].each do |type|
        @key_types.register(type)
        @value_types.register(type)
      end
      [integer_type, float_type, true_type, false_type, nil_type].each do
        @key_types.register(it)
      end
    end

    def dump(payload)
      metadata = Hash.new { |h, k| h[k] = {} }
      serialized =
        payload.to_h do |k, v|
          ktype = @key_types.by_value(k)
          dumped_key = ktype ? ktype.dump[k] : k
          metadata[dumped_key]["k"] = ktype.name if ktype
          vtype = @value_types.by_value(v)
          metadata[dumped_key]["v"] = vtype.name if vtype
          [dumped_key, vtype ? vtype.dump[v] : v]
        end
      [
        JSON.generate(serialized),
        (JSON.generate("serializer" => metadata) unless metadata.empty?),
      ]
    end

    def load(string, description)
      desc = description ? JSON.parse(description).fetch("serializer") : {}
      JSON
        .parse(string)
        .to_h do |k, v|
          entry = desc[k] || {}
          kname = entry["k"]
          vname = entry["v"]
          [
            kname ? @key_types.by_name(kname).load[k] : k,
            vname ? @value_types.by_name(vname).load[v] : v,
          ]
        end
    end

    private

    def symbol_type = Type.new(Symbol, "Symbol", IDENTITY, lambda { it.to_sym })

    def date_type =
      Type.new(Date, "Date", IDENTITY, lambda { Date.iso8601(it) })

    def time_type =
      Type.new(Time, "Time", lambda { it.iso8601 }, lambda { Time.iso8601(it) })

    def binary_type
      Type.new(
        lambda { String === it && it.encoding == Encoding::BINARY },
        "ASCII-8BIT",
        lambda { [it].pack("m0") },
        lambda { it.unpack1("m0") },
      )
    end

    def integer_type =
      Type.new(Integer, "Integer", IDENTITY, lambda { Integer(it) })

    def float_type = Type.new(Float, "Float", IDENTITY, lambda { Float(it) })

    def true_type =
      Type.new(TrueClass, "TrueClass", IDENTITY, lambda { |_| true })

    def false_type =
      Type.new(FalseClass, "FalseClass", IDENTITY, lambda { |_| false })

    def nil_type = Type.new(nil, "NilClass", IDENTITY, lambda { |_| })

    def optional_big_decimal_type
      return [] unless defined?(BigDecimal)
      [
        Type.new(
          BigDecimal,
          "BigDecimal",
          lambda { it.to_s("F") },
          lambda { BigDecimal(it) },
        ),
      ]
    end
  end
end
