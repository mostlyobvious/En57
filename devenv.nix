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
  ];

  enterShell = ''
    export MUTANT_SINCE="''${MUTANT_SINCE:-HEAD}"
  '';

  tasks = {
    "dev:setup".exec = "bundle install --quiet";
    "devenv:enterShell".after = [ "dev:setup" ];
    "dev:format" = {
      exec = "treefmt";
      after = [ "dev:setup" ];
    };
    "test:unit" = {
      exec = "bin/m test";
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
