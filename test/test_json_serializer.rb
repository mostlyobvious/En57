# frozen_string_literal: true

require "test_helper"
require "date"
require "time"
require "bigdecimal"
require "json"
require "openssl"

module En57
  class TestJsonSerializer < Minitest::Test
    cover JsonSerializer

    class Example < Data.define(:name, :value, :serialized, :klass)
      NATIVE_TYPES = %w[
        String
        Integer
        Float
        TrueClass
        FalseClass
        NilClass
      ].freeze
      private_constant :NATIVE_TYPES

      def json_native? = NATIVE_TYPES.include?(klass)
    end

    cipher_bytes =
      begin
        cipher = OpenSSL::Cipher.new("aes-128-cbc")
        cipher.encrypt
        cipher.key = "\x00".b * 16
        cipher.iv = "\x00".b * 16
        cipher.update("hello") + cipher.final
      end

    [
      %w[string str str String],
      ["symbol", :sym, "sym", "Symbol"],
      ["date", Date.new(2024, 1, 1), "2024-01-01", "Date"],
      ["time", Time.utc(2024, 1, 1, 12, 0, 0), "2024-01-01T12:00:00Z", "Time"],
      ["big_decimal", BigDecimal("1.5"), "1.5", "BigDecimal"],
      ["binary", cipher_bytes, [cipher_bytes].pack("m0"), "ASCII-8BIT"],
      ["integer", 100, 100, "Integer"],
      ["float", 1.5, 1.5, "Float"],
      ["true", true, true, "TrueClass"],
      ["false", false, false, "FalseClass"],
      ["nil", nil, nil, "NilClass"],
    ].map { Example.new(*it) }
      .permutation(2) do |k, v|
        meta = Hash.new { |h, k| h[k] = {} }
        meta[k.serialized]["k"] = k.klass unless k.klass == "String"
        meta[k.serialized]["v"] = v.klass unless v.json_native?

        payload = { k.value => v.value }
        serialized = JSON.dump(k.serialized => v.serialized)
        description = meta.empty? ? nil : JSON.dump("serializer" => meta)

        define_method("test_dump_#{k.name}_key_#{v.name}_value") do
          assert_equal([serialized, description], serializer.dump(payload))
        end

        define_method("test_load_#{k.name}_key_#{v.name}_value") do
          assert_equal(payload, serializer.load(serialized, description))
        end
      end

    def test_empty_meta_for_native_payload
      assert_equal(['{"kaka":"dudu"}', nil], serializer.dump("kaka" => "dudu"))
    end

    def test_load_handles_empty_description
      assert_equal(
        { "kaka" => "dudu" },
        serializer.load('{"kaka":"dudu"}', nil),
      )
    end

    private

    def serializer = JsonSerializer.new
  end
end
