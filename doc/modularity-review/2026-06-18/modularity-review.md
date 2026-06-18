# Modularity Review

**Scope**: Entire `en57` library — `lib/` (EventStore, Scope/Query, Repository, adapters, JsonSerializer, Migrator, Configuration) plus the PostgreSQL schema and stored functions in `db/schema/0.1.0.sql`
**Date**: 2026-06-18

## Executive Summary

`en57` is a [DCB-compatible](https://dcb.events) event store library for Ruby on PostgreSQL. It lets applications append events with optimistic-concurrency conditions (`fail_if`) and read them back through a fluent, tag- and type-filtered query DSL, pushing the consistency-boundary logic down into PL/pgSQL stored functions. Overall the design is **healthy and well-factored**: the connection adapters, serializer, and migrator are cleanly separated behind narrow [contracts](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/), and their low [volatility](https://coupling.dev/posts/dimensions-of-coupling/volatility/) keeps them out of trouble. The one finding that deserves real attention is the **implicit contract between the Ruby `Repository` and the SQL stored functions** — the wire format and the positional composite-type encoding are duplicated, stringly-typed knowledge spread across two languages in the most [volatile](https://coupling.dev/posts/dimensions-of-coupling/volatility/) part of the system. Because the gem and schema ship in lockstep, this is not a distributed-monolith problem — but it is a latent source of [fragility](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) that should be made explicit before the query surface grows.

## Coupling Overview

| Integration | [Strength](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) | [Distance](https://coupling.dev/posts/dimensions-of-coupling/distance/) | [Volatility](https://coupling.dev/posts/dimensions-of-coupling/volatility/) | [Balanced?](https://coupling.dev/posts/core-concepts/balance/) |
| ----------- | -------- | -------- | ---------- | --------- |
| `Repository` → SQL functions (`en57.append_events` / `en57.read_events`, `en57.event` type) | [Functional](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) / [Intrusive](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (implicit) | Medium — cross-language, but same repo/maintainer & lockstep release | **High** (core) | **No** — implicit high strength in the most volatile path |
| `Query` / `Criteria` → SQL criteria parsing | [Functional](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (implicit, shared wire format) | Medium (Ruby ↔ PL/pgSQL) | **High** (core) | **No** — same root cause as above |
| `Migrator` → database & schema layout | [Functional](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (own `PG.connect`, hardcoded schema name) | High (Ruby ↔ SQL, bypasses adapters) | Low (supporting) | Tolerable — low volatility neutralizes it |
| `Scope` ↔ `MergedScope` | [Functional](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (duplicated iteration logic) | Low (same file) | High (core) | Mostly — low distance, but duplication risks drift |
| `Repository` → `Configuration` (global `Singleton`) | [Functional](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (action at a distance) | Logical distance via global state | Low | Tolerable — low volatility, but a testability smell |
| `Repository` → adapters (`with_connection` / `with_transaction` / `serialization_error`) | [Contract](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (with implicit "yields raw `pg` connection") | Low (same module) | Low (generic) | **Yes** — balanced |
| `Repository` → `JsonSerializer` | [Contract](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (`dump` / `load`, pluggable) | Low (same module) | Low (generic) | **Yes** — balanced |
| `Scope` / `EventStore` → `Repository` | [Contract](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) / [Model](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (`read` yields `[event, position]`) | Low (same module) | Medium | **Yes** — balanced |

The bottom three rows are examples of [balanced coupling](https://coupling.dev/posts/core-concepts/balance/) and need no action; they are listed to show the contrast. The issues below cover the unbalanced rows.

## Issue: Implicit, two-language contract between the Repository and the SQL stored functions

**Integration**: `Repository` (+ `Query`/`Criteria`) → `en57.append_events` / `en57.read_events`
**Severity**: Significant

### Knowledge Leakage

The integration that carries the library's whole reason to exist — the DCB append/read semantics — is expressed as an **implicit wire format duplicated across Ruby and PL/pgSQL**, with no single place that defines it. Three distinct pieces of knowledge leak across the boundary:

1. **The positional layout of the `en57.event` composite type** ([intrusive coupling](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/)). `Repository#append` builds each record with `@record_encoder.encode([event.id, event.type, serialized, description, tags])` (`lib/en57/repository.rb:21-29`). The order and count of those five elements must match `CREATE TYPE en57.event AS (id, type, data, meta, tags)` (`db/schema/0.1.0.sql:21-27`) exactly and positionally. Nothing names the fields; the coupling is to an *implementation detail* of the type definition.

2. **The criteria/`append_condition` JSON shape** ([functional coupling](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/)). `Criteria#matcher` emits `{types:, tags:, after:}` (`lib/en57/query.rb:23-27`); `Repository` wraps it as `{fail_if_events_match: [...]}` (`lib/en57/repository.rb:31-36`); and both SQL functions reach into exactly those keys — `append_condition -> 'fail_if_events_match'`, `criterion -> 'types'`, `-> 'tags'`, `->> 'after'` (`db/schema/0.1.0.sql:40-58`, `163-208`). The same vocabulary is hand-maintained in three files and two languages.

3. **The result column set** — `position`, `conflicting_events`, `id`, `type`, `data`, `meta`, `tags` — is fetched by name in `deserialize_event` (`lib/en57/repository.rb:57-67`, `121-137`) and must match the `RETURNS` clauses of both functions.

None of this is encapsulated by an [integration contract](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/). It is the textbook description of intrusive coupling: *"both fragile and implicit."*

### Complexity Impact

Because the contract is stringly-typed JSON and a positional tuple, **no tool spans the boundary**. The Ruby test suite cannot see a column reorder in the SQL; the PostgreSQL function cannot see a renamed JSON key in Ruby. A developer changing one side has to hold both representations — Ruby encoder, JSON vocabulary, and PL/pgSQL parser — in working memory simultaneously to reason about correctness. That is more than the 4±1 units of working memory the model warns about, so the outcome of a change becomes [unpredictable](https://coupling.dev/posts/core-concepts/complexity/): it surfaces only at runtime, as a deserialization error or a silently wrong query result, rather than at edit time.

### Cascading Changes

This area is the [core subdomain](https://coupling.dev/posts/dimensions-of-coupling/volatility/) and is demonstrably [volatile](https://coupling.dev/posts/dimensions-of-coupling/volatility/) — recent commits added *batched reads* and *conflicting-events-on-failure*, both of which touched exactly this boundary. Concrete cascades that the current design makes risky:

- **Adding a new query dimension** (e.g. an `before`/upper-bound position, or correlation/causation filters from `doc/ideas.md`) requires coordinated edits in `Criteria#matcher`, the `Scope` DSL, and *both* SQL functions' JSON parsing — four edit sites, no compiler to catch an omission.
- **Reordering or inserting a field in the `en57.event` composite type** silently breaks the positional encoder with no failing unit test until an integration run hits the database.
- **Renaming a wire key** (`tags` → `tag_values`, say) compiles cleanly on both sides and fails only at runtime.

The mitigating factor — and the reason this is **Significant rather than Critical** — is the confirmed **lockstep lifecycle**: the gem and the schema are released and migrated together by a single maintainer, so there is no [lifecycle/deployment distance](https://coupling.dev/posts/dimensions-of-coupling/distance/) and no version-skew window. Both sides always change in the same release, which is genuine [high cohesion](https://coupling.dev/posts/core-concepts/balance/). What remains is the *cognitive* distance of co-evolving an implicit contract across two languages — cheap to get wrong, not cheap to verify.

### Recommended Improvement

Keep the components exactly where they are — the strength is essential (the library deliberately pushes consistency logic into PostgreSQL) and the distance is already minimized by lockstep, so splitting or moving nothing is warranted. Instead, **make the implicit contract explicit** to convert [intrusive coupling into contract coupling](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/):

- **Eliminate the positional encoding.** Encode the `en57.event` record with named fields, or add a single Ruby constant (e.g. `EVENT_RECORD_FIELDS = %i[id type data meta tags]`) that drives the encoder, and a `pg_regress` assertion that the composite type's column order matches it. This removes the most fragile, most implicit leak at near-zero cost.
- **Define the wire vocabulary once.** Promote the criteria/`append_condition` keys (`types`, `tags`, `after`, `fail_if_events_match`) into named constants on the Ruby side and reference them everywhere they are generated, and add a contract test that round-trips a representative criteria document through `read_events`/`append_events` so a key rename on either side fails a test rather than production.
- **Pin the contract with characterization tests at the boundary.** The existing `test/pg_regress` suite is the natural home: one fixture per wire-format element so any change to the JSON shape or column set must be acknowledged in an expected-output file.

**Trade-off**: this adds a small amount of indirection and a handful of boundary tests — modest ceremony for code that is otherwise pleasantly direct. It is worthwhile precisely because this is the *most volatile* boundary in the system: every future query feature crosses it, and an explicit contract turns each of those crossings from a four-site memory exercise into a single, test-guarded change.

## Issue: Migrator bypasses the adapter abstraction and re-encodes schema knowledge

**Integration**: `Migrator` → database & `en57` schema layout
**Severity**: Minor

### Knowledge Leakage

`Migrator` opens its own connection with `PG.connect(@connection_string)` (`lib/en57/migrator.rb:155-160`) rather than going through the [adapter contract](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) (`with_connection`) that the rest of the library uses. It also independently knows the `en57` schema name and the `public.en57_schema_info` bookkeeping table — knowledge that overlaps with the `en57.*`-qualified SQL strings baked into `Repository`. There are thus two separate strategies for "how `en57` talks to PostgreSQL."

### Complexity Impact

The duplication is small but means a developer reasoning about connection handling, pooling, or schema naming has to know that migration is the one path that does *not* obey the adapter abstraction. It is a low-grade inconsistency rather than a cascading hazard.

### Cascading Changes

Migration is a [supporting subdomain](https://coupling.dev/posts/dimensions-of-coupling/volatility/) with **low volatility** — `migrate!` currently only installs a fresh schema and explicitly refuses version diffs (`lib/en57/migrator.rb:29-43`). Per the [balance rule](https://coupling.dev/posts/core-concepts/balance/), `BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY`: the low volatility term neutralizes the imbalance, so this is tolerable today. It would only start to bite if migration grew richer (multi-version upgrades) while still bypassing the shared connection plumbing.

### Recommended Improvement

No action required now. When versioned migrations land, consider routing the `Migrator` through the same adapter interface (or a thin connection abstraction) so connection handling and schema naming live in one place. Until then, the duplication is cheap to carry and splitting it out would add distance for no volatility-justified benefit.

## Issue: Duplicated iteration logic between Scope and MergedScope

**Integration**: `Scope` ↔ `MergedScope`
**Severity**: Minor

### Knowledge Leakage

`Scope` and `MergedScope` carry nearly identical implementations of `each`, `each_with_position`, and `to_query`, and both delegate to `@repository.read(@query)` (`lib/en57/scope.rb:14-26`, `40-52`). The knowledge of *how a query is iterated and how positions are threaded through* is [duplicated functional knowledge](https://coupling.dev/posts/dimensions-of-coupling/integration-strength/) held in two classes.

### Complexity Impact

The [distance](https://coupling.dev/posts/dimensions-of-coupling/distance/) is the lowest possible — the two classes sit in the same file, visible together — so by the [balance rule](https://coupling.dev/posts/core-concepts/balance/) high strength at low distance is [high cohesion](https://coupling.dev/posts/core-concepts/balance/), not a real imbalance. The only risk is **drift**: because the duplication is implicit (no shared base/mixin), a change to read iteration — exactly the kind of change the recent batched-reads work represents — must be remembered in both places.

### Cascading Changes

Any change to iteration semantics (a new `each_*` variant, lazy/eager changes, instrumentation hooks from the `doc/ideas.md` pub-sub plans) currently means editing both classes. Cheap to perform (same file) but easy to half-apply.

### Recommended Improvement

Extract the shared iteration behavior into a small module included by both classes, or have `MergedScope` and `Scope` share a common ancestor for the read-side methods. This keeps strength high and distance low (a module in the same file) while removing the duplication, so the cohesion stays but the drift risk goes away. The trade-off is one extra indirection layer — justified because this code lives in the volatile core query surface.

## Issue: Repository reads append/read tuning from a global Configuration singleton

**Integration**: `Repository` → `Configuration` (global `Singleton`)
**Severity**: Minor

### Knowledge Leakage

`Repository` reaches into the global `En57.configuration` for `append_retries` and `read_batch_size` *at call time*, deep inside `append` and `read` (`lib/en57/repository.rb:44`, `82`), while the `serializer` is injected once via the constructor default (`lib/en57/repository.rb:7`). The same concept — runtime tuning — is sourced two different ways, and two of the three values are pulled from process-global state rather than passed in.

### Complexity Impact

Global, frozen [singleton](https://coupling.dev/posts/dimensions-of-coupling/distance/) access is a form of logical distance: the dependency is invisible at the `Repository` boundary, which complicates testing (a test must mutate global state to exercise retry/batch behavior) and obscures what a `Repository` actually needs to function. This is a cohesion/testability smell, not a cascading-change generator.

### Cascading Changes

Configuration is **low volatility**, so the [balance rule](https://coupling.dev/posts/core-concepts/balance/)'s `NOT VOLATILITY` term keeps this tolerable. The cost is paid in test friction rather than production change-amplification.

### Recommended Improvement

For consistency, source all three tunables the same way the serializer already is — read them at construction time (defaulting from `En57.configuration`) and store them on the instance, rather than reaching into the global mid-method. This makes `Repository`'s dependencies explicit at its boundary and removes global state from the hot path, at the cost of a slightly larger constructor. Low priority given the low volatility.

---

_This analysis was performed using the [Balanced Coupling](https://coupling.dev) model by [Vlad Khononov](https://vladikk.com)._
