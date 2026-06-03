# frozen_string_literal: true

require "singleton"

module En57
  class Configuration
    include Singleton

    attr_accessor :append_retries, :read_batch_size, :serializer

    def initialize
      @append_retries = 9
      @read_batch_size = 1000
      @serializer = JsonSerializer.new
    end
  end
end
