{ pkgs, lib, ... }:

{
  languages.ruby.enable = true;
  languages.ruby.version = "4.0.5";

  packages = [
    pkgs.postgresql_18
    pkgs.postgresql_18.pg_config
    pkgs.pgformatter
    pkgs.jq
    pkgs.libyaml
  ];

  env.PG_REGRESS = "${pkgs.postgresql_18.dev}/lib/pgxs/src/test/regress/pg_regress";

  enterShell = ''
    export MUTANT_SINCE="''${MUTANT_SINCE:-HEAD}"
    bundle install --quiet
  '';

  tasks = {
    "app:format".exec = "bin/rake format";
    "app:test".exec = "bin/rake test";
    "app:mutate".exec = "bin/mutant run";
    "app:pg-regress".exec = "bin/rake pg_regress";
    "app:check".exec = "bin/rake"; # default: test + mutate_since
  };

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
  claude.code.hooks.format-ruby = {
    name = "Format Ruby with syntax_tree";
    hookType = "PostToolUse";
    matcher = "Write|Edit";
    command = ''
      jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; case "$f" in *.rb) bin/stree write "$f" ;; esac; } 2>/dev/null || true
    '';
  };
}
