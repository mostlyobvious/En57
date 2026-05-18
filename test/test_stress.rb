# frozen_string_literal: true

require "test_helper"

module En57
  class TestStress < IntegrationTest
    ADAPTERS.each do |name, factory|
      define_method(
        "test_#{name}_only_one_writer_can_consume_account_credits",
      ) do
        with_event_store(factory) do |event_store|
          event_store.append(
            [
              Event.new(
                type: "CreditsToppedUp",
                data: {
                  amount: 100,
                },
                tags: [account_tag],
              ),
            ],
          )

          barrier = Concurrent::CyclicBarrier.new(concurrency)
          threads =
            Array.new(concurrency) do
              Thread.new do
                Thread.current.report_on_exception = false

                account_scope = event_store.read.with_tag(account_tag)
                barrier.wait

                event_store.append(
                  [
                    Event.new(
                      type: "CreditsUsed",
                      data: {
                        amount: 100,
                      },
                      tags: [account_tag],
                    ),
                  ],
                  fail_if: account_scope.of_type("CreditsUsed"),
                )
              rescue PG::TRSerializationFailure => e
                e
              end
            end

          assert_equal(
            (concurrency - 1),
            threads.map(&:value).reject { Success === it }.size,
          )
          assert_equal(
            1,
            event_store
              .read
              .with_tag(account_tag)
              .of_type("CreditsUsed")
              .each
              .count,
          )
        end
      end
    end

    private

    def with_event_store(factory)
      yield EventStore.new(Repository.new(factory.call, JsonSerializer.new))
    end

    def concurrency = POOL_SIZE

    def account_tag = "account:x"
  end
end
