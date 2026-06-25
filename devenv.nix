{
  pkgs,
  lib,
  config,
  ...
}:

{
  languages.ruby.enable = true;
  languages.ruby.version = "4.0.5";
  languages.ruby.bundler.package =
    (pkgs.bundler.override { ruby = config.languages.ruby.package; }).overrideAttrs
      (_: rec {
        version = "4.0.15";
        src = pkgs.fetchurl {
          url = "https://rubygems.org/gems/bundler-${version}.gem";
          hash = "sha256-pM64gv6UoOCsY80IE5Mrv9YxoU5awLeXUYmxmk0o2ec=";
        };
      });

  packages = [
    pkgs.postgresql_18
    pkgs.postgresql_18.pg_config
    pkgs.sqlfluff
    pkgs.jq
    pkgs.libyaml
    pkgs.pi-coding-agent
    pkgs.claude-code
    pkgs.nodejs
  ];

  enterShell = ''
    export MUTANT_SINCE="''${MUTANT_SINCE:-HEAD}"
  '';

  services.postgres = {
    enable = true;
    package = pkgs.postgresql_18;
    initialDatabases =
      let
        en57 = name: {
          inherit name;
          schema = ./db/schema/0.1.0.sql;
        };
        res = name: {
          inherit name;
          schema = ./db/seeds/res.sql;
        };
      in
      [
        (en57 "main")
        (en57 "append-no-fail-if")
        (en57 "append-no-fail-if-ar")
        (en57 "append-non-conflicting-tags")
        (en57 "concurrent-append-no-fail-if")
        (en57 "concurrent-append-no-fail-if-ar")
        (en57 "concurrent-append-conflicting-tags")
        (en57 "concurrent-append-non-conflicting-tags")
        (en57 "concurrent-append-non-conflicting-tags-seeded")
        (res "res-append-stream-any")
        (res "res-concurrent-append-non-conflicting-streams")
        (res "res-concurrent-append-conflicting-streams")
        (en57 "regress")
      ];
  };

  files =
    let
      commitSkill = ''
        ---
        name: commit
        description: Create a git commit following project conventions. Use this skill when asked to commit changes, group changes into commits, or prepare commits.
        ---

        # Commit

        ## Format

        ```
        <Capitalized imperative subject ≤50 chars>

        <Body wrapped at 72 cols, explaining why.>
        ```

        - Subject: Capitalized imperative ("Fix bug", not "Fixed"). No trailing period.
        - Blank line between subject and body. Body wrapped at 72 cols.
        - Prefer `-` bullet points in the body over prose paragraphs. Hanging indent for wrapped lines.
        - Body explains **why** (and, when non-obvious, **how** and **what effects** — benchmarks, side effects, follow-ups). Skip questions that don't apply. Never restate the diff.
        - Prefer bullet point

        ## Scope

        - One logical change per commit; split unrelated concerns.

        ## Procedure

        1. `git status` + `git diff --staged` (and `git diff` if unstaged) to confirm scope.
        2. Draft subject + body.
        3. Present the staged files and message for approval
        4. Wait for user confirmation before committing
        5. No `--no-verify`. No amending published commits. No force-push without explicit request.
      '';
      mutantSkill = builtins.readFile (
        pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/mbj/mutant/v0.16.2/SKILL.md";
          hash = "sha256-749LKKVW6riDQeBYVVLxMEnhx6DuFOaUlqxjRSxs8aY=";
        }
      );
    in
    {
      ".agents/skills/commit/SKILL.md".text = commitSkill;
      ".agents/skills/mutant/SKILL.md".text = mutantSkill;
      ".claude/skills/commit/SKILL.md".text = commitSkill;
      ".claude/skills/mutant/SKILL.md".text = mutantSkill;
      ".pi/settings.json".json = {
        packages = [ "npm:pi-edit-hooks@0.2.1" ];
      };
      ".pi/edit-hooks.json".json = {
        onEdit = {
          "*" = "treefmt {file}";
        };
        onStop = {
          "*" = "devenv tasks run test";
        };
      };
    };

  tasks = {
    "dev:setup".exec = "bundle install --quiet";
    "devenv:enterShell".after = [ "dev:setup" ];
    "dev:format" = {
      exec = "treefmt";
      after = [ "dev:setup" ];
    };
    "test:unit" = {
      exec = ''
        ruby -Itest -Ilib <<'RUBY'
          require "bundler/setup"
          Dir["test/test_*.rb"].sort.each { require File.expand_path(_1) }
          Minitest::Runnable.runnables.reject! { _1.superclass != Minitest::Test || _1 == En57::IntegrationTest }
        RUBY
      '';
      after = [ "dev:setup" ];
    };
    "test:integration" = {
      exec = ''
        ruby -Itest -Ilib <<'RUBY'
          require "bundler/setup"
          Dir["test/test_*.rb"].sort.each { require File.expand_path(_1) }
          Minitest::Runnable.runnables.reject! { _1.superclass != En57::IntegrationTest }
        RUBY
      '';
      after = [ "dev:setup" ];
    };
    "test:mutate" = {
      exec = ''bin/mutant run --since "''${MUTANT_SINCE:-HEAD}"'';
      after = [ "dev:setup" ];
    };
    "test:pg".exec = "pg-regress";
  };

  treefmt.enable = true;
  treefmt.config = {
    programs = {
      nixfmt.enable = true;
    };
    settings.formatter = {
      ruby = {
        command = "stree";
        options = [ "write" ];
        includes = [ "*.rb" ];
      };
      sql = {
        command = "sqlfluff";
        options = [
          "format"
          "--dialect"
          "postgres"
          "--exclude-rules"
          "LT05"
        ];
        includes = [ "db/**/*.sql" ];
      };
    };
  };

  scripts.pg-regress.exec = ''
    set -euo pipefail
    cd "$DEVENV_ROOT"

    pg_regress=${pkgs.postgresql_18.dev}/lib/pgxs/src/test/regress/pg_regress
    bindir=${pkgs.postgresql_18}/bin
    dbname=regress
    user=''${PGUSER:-$(id -un)}

    "$bindir/dropdb" -h "$PGHOST" -U "$user" --if-exists "$dbname"
    "$bindir/createdb" -h "$PGHOST" -U "$user" "$dbname"
    "$bindir/psql" -h "$PGHOST" -U "$user" -d "$dbname" \
      -v ON_ERROR_STOP=1 -q -f db/schema/0.1.0.sql

    rm -rf test/pg_regress/results
    mkdir -p test/pg_regress/results

    "$pg_regress" \
      --use-existing \
      --host="$PGHOST" \
      --user="$user" \
      --dbname="$dbname" \
      --inputdir=test/pg_regress \
      --outputdir=test/pg_regress/results \
      --expecteddir=test/pg_regress \
      --bindir="$bindir" \
      --schedule=test/pg_regress/schedule_existing
  '';

  claude.code.enable = true;
  claude.code.hooks = {
    format = {
      name = "Format edited files with treefmt";
      hookType = "PostToolUse";
      matcher = "Write|Edit";
      command = ''
        jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; treefmt "$f"; } 2>/dev/null || true
      '';
    };
    test = {
      name = "Run the test namespace on stop";
      hookType = "Stop";
      command = ''
        input=$(cat)
        cd "''${DEVENV_ROOT:-.}" || exit 0
        devenv tasks run test 1>&2 && exit 0
        [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
        exit 2
      '';
    };
  };
}
