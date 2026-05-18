# frozen_string_literal: true

require "test_helper"

module En57
  class TestEn57 < Minitest::Test
    cover En57

    def test_that_it_has_a_version_number
      refute_nil VERSION
    end

    def test_requiring_en57_without_sequel_skips_sequel_adapter
      assert_ruby(<<~RUBY)
        require "en57"
        abort "loaded SequelAdapter" if defined?(En57::SequelAdapter)
      RUBY
    end

    def test_requiring_en57_without_active_record_skips_active_record_adapter
      assert_ruby(<<~RUBY)
        require "en57"
        abort "loaded ActiveRecordAdapter" if defined?(En57::ActiveRecordAdapter)
      RUBY
    end

    def test_configuration_default_serializer
      assert_kind_of JsonSerializer, En57.configuration.serializer
    end

    def test_configuration_default_retry_settings
      with_empty_configuration do
        assert_equal 10, En57.configuration.max_retries
      end
    end

    def test_configure
      with_empty_configuration do
        serializer = Object.new
        En57.configure { |c| c.serializer = serializer }

        assert_equal serializer, En57.configuration.serializer
      end
    end

    def test_configure_disallows_further_modifications_after_boot
      with_empty_configuration do
        serializer = Object.new
        En57.configure { |c| c.serializer = serializer }

        assert_raises(FrozenError) do
          En57.configure { |c| c.serializer = serializer }
        end
      end
    end

    private

    def with_empty_configuration
      En57.stub(:configuration, Class.new(Configuration).instance) { yield }
    end

    def assert_ruby(script)
      reader, writer = IO.pipe
      pid =
        Process.spawn(
          RbConfig.ruby,
          "-Ilib",
          "-e",
          script,
          out: writer,
          err: writer,
        )
      writer.close
      output = reader.read
      _, status = Process.wait2(pid)

      assert status.success?, output
    ensure
      reader&.close
    end
  end
end
