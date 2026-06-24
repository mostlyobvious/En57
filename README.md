# En57

[DCB-compatible](https://dcb.events) event store library in Ruby with support for PostgreSQL. Join the [Discord community](https://discord.gg/DxwH7GfgVV).

## Usage

### Set up the database schema

En57 owns its PostgreSQL schema and tracks the installed schema version in
the database. Add the rake tasks to your application's `Rakefile`:

```ruby
require "en57/tasks"
```

Then install or update the schema with `DATABASE_URL`:

```sh
DATABASE_URL=postgres://localhost:5432/en57 bundle exec rake en57:migrate
```

To inspect the current schema status without applying changes:

```sh
DATABASE_URL=postgres://localhost:5432/en57 bundle exec rake en57:status
```

Run `en57:migrate` before using the event store for the first time.

### Connect with raw pg

Use `EventStore.for_pg` when En57 should own a pg connection.

```ruby
event_store = En57::EventStore.for_pg("postgres://localhost:5432/en57")
```

### Connect with Sequel

Use `EventStore.for_sequel` when your app already owns a Sequel database.

```ruby
database = Sequel.connect("postgres://localhost:5432/en57")

event_store = En57::EventStore.for_sequel(database)
```

### Connect with ActiveRecord

Use `EventStore.for_active_record` when your app uses ActiveRecord.

```ruby
ActiveRecord::Base.establish_connection("postgres://localhost:5432/en57")

event_store = En57::EventStore.for_active_record
```

### Append events unconditionally

```ruby
event_store.append(
  [
    En57::Event.new(
      type: "OrderPlaced",
      data: { amount: 100 },
      tags: ["order_id:123", "customer:42"],
    ),
  ],
)
```

### Read all events

```ruby
events = event_store.read.each.to_a
```

### Read events with positions

```ruby
event, position = event_store.read.each_with_position.first
```

### Read events filtered by tags

```ruby
events = event_store.read.with_tag("order_id:123", "customer:42").each.to_a
```

### Read events after a position

```ruby
events = event_store.read.after(42).each.to_a
```

### Read events filtered by merged scopes

```ruby
orders = event_store.read.of_type("OrderPlaced").with_tag("order_id:123")
price_changes = event_store.read.of_type("PriceChanged")

events = (orders | price_changes).each.to_a
```

### Conditional write (optimistic concurrency style)

Example: consume credits only once per account.

```ruby
account_scope = event_store.read.with_tag("account:x")

result = event_store.append(
  [
    En57::Event.new(
      type: "CreditsUsed",
      data: { amount: 100 },
      tags: ["account:x"],
    ),
  ],
  fail_if: account_scope.of_type("CreditsUsed"),
)

case result
in En57::Success(position:)
  # credits consumed at event position
in En57::Failure(position:, conflicting_events:)
  # lost the race; conflicting_events contains the events that matched
  # the fail_if condition, with position set to the latest conflict
end
```

To ignore events at or before a known position, scope the `fail_if` condition
with `after`.

```ruby
last_read_event_position = 42

event_store.append(
  [En57::Event.new(type: "CreditsUsed", tags: ["account:x"])],
  fail_if: event_store.read.of_type("CreditsUsed").after(last_read_event_position),
)
```

### Conditional write for email uniqueness

Example: ensure no event exists with this email tag before writing.

```ruby
email_tag = "email:alice@example.com"

result = event_store.append(
  [
    En57::Event.new(
      type: "UserRegistered",
      data: { name: "Alice" },
      tags: [email_tag],
    ),
  ],
  fail_if: event_store.read.with_tag(email_tag),
)

case result
in En57::Success(position:)
  # user registered at event position
in En57::Failure(position:, conflicting_events:)
  # email already used; conflicting_events contains the matching event
end
```

## Development

The development environment is managed with [devenv](https://devenv.sh). It
pins the Ruby and PostgreSQL toolchain through Nix, so the only prerequisites
are Nix (with flakes) and devenv.

Enter the environment:

```sh
devenv shell
```

This provides Ruby, PostgreSQL, and the formatters, and installs the gem
dependencies (`bundle install`, via the `dev:setup` task) on entry.

Tasks are run with `devenv tasks run`:

| Task | What it does |
|------|--------------|
| `test` | Run the whole `test:` namespace (unit, mutation, pg_regress) |
| `test:unit` | Run the unit tests (`bin/m test`) |
| `test:mutate` | Run mutation testing (`mutant`) for changes since `MUTANT_SINCE` (defaults to `HEAD`) |
| `test:pg` | Run the `pg_regress` suite against an ephemeral PostgreSQL |
| `dev:format` | Format Ruby and SQL with [treefmt](https://treefmt.com) (syntax_tree + sqlfluff) |

`pg-regress` is also available as a standalone script in the shell.

CI runs `devenv tasks run test`. The devenv config also wires up Claude Code
hooks: edited files are formatted with treefmt, and the test suite runs at the
end of each agent loop.
