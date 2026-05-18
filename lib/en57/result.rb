# frozen_string_literal: true

module En57
  Success =
    Data.define(:position) do
      def success? = true
      def failure? = false
    end

  Failure =
    Data.define(:position, :conflicting_events) do
      def success? = false
      def failure? = true
    end
end
