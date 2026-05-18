# frozen_string_literal: true

require "singleton"

module En57
  class Configuration
    include Singleton

    attr_accessor :serializer, :max_retries

    def initialize
      @serializer = JsonSerializer.new
      @max_retries = 10
    end
  end
end
