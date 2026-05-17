# frozen_string_literal: true

require "singleton"

module En57
  class Configuration
    include Singleton

    attr_accessor :serializer

    def initialize
      @serializer = JsonSerializer.new
    end
  end
end
