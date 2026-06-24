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
    bundle install --quiet
  '';

  tasks = {
    "app:format".exec = "treefmt";
    "app:test".exec = "bin/rake test";
    "app:mutate".exec = "bin/mutant run";
    "app:check".exec = "bin/rake"; # default: test + mutate_since
  };

  # treefmt drives all formatters (Ruby via syntax_tree, SQL via sqlfluff).
  treefmt.enable = true;
  treefmt.config = {
    projectRootFile = "devenv.nix";
    settings.formatter = {
      ruby = {
        command = "stree";
        options = [ "write" ];
        includes = [ "*.rb" ];
      };
      sql = {
        command = "sqlfluff";
        options = [ "format" ];
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

  git-hooks.hooks.rake = {
    enable = true;
    name = "rake (test + mutate_since)";
    entry = "${pkgs.writeShellScript "rake-precommit" ''
      export MUTANT_SINCE="''${MUTANT_SINCE:-HEAD}"
      exec bin/rake
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
