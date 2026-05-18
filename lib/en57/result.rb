# frozen_string_literal: true

module En57
  module Result
    Success =
      Data.define(:position) do
        def success? = true
        def failure? = false
      end

    Failure =
      Data.define(:position) do
        def success? = false
        def failure? = true
      end

    def self.success(position:) = Success.new(position:)

    def self.failure(position:) = Failure.new(position:)
  end
end
