{ pkgs, lib, ... }:

{
  languages.ruby.enable = true;
  languages.ruby.version = "4.0.5";

  packages = [
    pkgs.postgresql_18
    pkgs.postgresql_18.pg_config
    pkgs.sqlfluff
    pkgs.jq
    pkgs.libyaml
  ];

  enterShell = ''
    export MUTANT_SINCE="''${MUTANT_SINCE:-HEAD}"
  '';

  tasks = {
    "app:setup".exec = "bundle install --quiet";
    "devenv:enterShell".after = [ "app:setup" ];
    "app:format".exec = "treefmt";

    "test:unit" = {
      exec = "bin/m test";
      after = [ "app:setup" ];
    };
    "test:mutate" = {
      exec = ''bin/mutant run --since "''${MUTANT_SINCE:-HEAD}"'';
      after = [ "app:setup" ];
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

  # Self-contained pg_regress run: spin up an ephemeral PostgreSQL with the
  # Nix server binaries, load the schema, run the regression schedule, then
  # tear it down. No Rakefile task, no gem, no env-var paths.
  scripts.pg-regress.exec = ''
    set -euo pipefail
    cd "$DEVENV_ROOT"

    pg_regress=${pkgs.postgresql_18.dev}/lib/pgxs/src/test/regress/pg_regress
    bindir=${pkgs.postgresql_18}/bin
    workdir=$(mktemp -d)
    datadir=$workdir/data
    socketdir=$workdir/socket
    dbname=en57_regress
    mkdir -p "$socketdir"

    cleanup() {
      "$bindir/pg_ctl" -D "$datadir" -m immediate stop >/dev/null 2>&1 || true
      rm -rf "$workdir"
    }
    trap cleanup EXIT

    "$bindir/initdb" -D "$datadir" -U postgres --auth=trust >/dev/null
    "$bindir/pg_ctl" -D "$datadir" -w \
      -o "-k $socketdir -c listen_addresses='''" start >/dev/null
    "$bindir/createdb" -h "$socketdir" -U postgres "$dbname"
    "$bindir/psql" -h "$socketdir" -U postgres -d "$dbname" \
      -v ON_ERROR_STOP=1 -q -f db/schema/0.1.0.sql

    rm -rf test/pg_regress/results
    mkdir -p test/pg_regress/results

    "$pg_regress" \
      --use-existing \
      --host="$socketdir" \
      --user=postgres \
      --dbname="$dbname" \
      --inputdir=test/pg_regress \
      --outputdir=test/pg_regress/results \
      --expecteddir=test/pg_regress \
      --bindir="$bindir" \
      --schedule=test/pg_regress/schedule_existing
  '';

  git-hooks.hooks.test = {
    enable = true;
    name = "test:unit + test:mutate";
    entry = "${pkgs.writeShellScript "pre-commit-test" ''
      exec devenv tasks run test:unit test:mutate
    ''}";
    pass_filenames = false;
    language = "system";
    stages = [ "pre-commit" ];
  };

  claude.code.enable = true;
  claude.code.hooks.git-hooks-run.enable = false;
  claude.code.hooks.format = {
    name = "Format edited files with treefmt";
    hookType = "PostToolUse";
    matcher = "Write|Edit";
    command = ''
      jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; treefmt "$f"; } 2>/dev/null || true
    '';
  };
}
