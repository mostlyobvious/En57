# frozen_string_literal: true

require "singleton"

module En57
  class Configuration
    include Singleton

    attr_accessor :append_retries, :serializer

    def initialize
      @append_retries = 9
      @serializer = JsonSerializer.new
    end
  end
end
