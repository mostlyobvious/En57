# frozen_string_literal: true

require "pg"
require "securerandom"

module En57
  module EphemeralDatabase
    extend self

    ADMIN_URL = "postgres:///postgres"

    def with(template: nil, prefix: "en57")
      name = "#{prefix}.#{SecureRandom.hex(8)}"
      admin = PG.connect(ADMIN_URL)
      statement = "CREATE DATABASE #{PG::Connection.quote_ident(name)}"
      statement +=
        " TEMPLATE #{PG::Connection.quote_ident(template)}" if template
      execute(admin, statement)
      yield "postgres:///#{name}"
    ensure
      if admin
        execute(
          admin,
          "DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(name)} " \
            "WITH (FORCE)",
        )
      end
      admin&.close
    end

    private

    def execute(connection, statement) = connection.exec(statement)
  end
end
