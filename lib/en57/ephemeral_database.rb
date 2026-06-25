# frozen_string_literal: true

require "pg"
require "securerandom"
require "uri"

module En57
  module EphemeralDatabase
    extend self

    ADMIN_URL = "postgres:///postgres"

    def with(template: nil, prefix: "en57", admin_url: ADMIN_URL)
      name = "#{prefix}.#{SecureRandom.hex(8)}"
      admin = PG.connect(admin_url)
      statement = "CREATE DATABASE #{PG::Connection.quote_ident(name)}"
      statement +=
        " TEMPLATE #{PG::Connection.quote_ident(template)}" if template
      execute(admin, statement)
      yield database_url(admin_url, name)
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

    def database_url(admin_url, name)
      URI.parse(admin_url).tap { it.path = "/#{name}" }.to_str
    end

    def execute(connection, statement) = connection.exec(statement)
  end
end
