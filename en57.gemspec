# frozen_string_literal: true

require_relative "lib/en57/version"

Gem::Specification.new do |spec|
  spec.name = "en57"
  spec.version = En57::VERSION
  spec.authors = ["Paweł Pacana"]
  spec.email = ["me@mostlyobvio.us"]

  spec.summary =
    "DCB-compatible event store library in Ruby with support for PostgreSQL."
  spec.homepage = "https://github.com/mostlyobvious/en57"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mostlyobvious/en57"
  spec.metadata[
    "changelog_uri"
  ] = "https://github.com/mostlyobvious/en57/blob/main/CHANGELOG.md"

  spec.files =
    Dir["lib/**/*", "db/schema/**/*.sql"] -
      %w[bin/benchmark lib/en57/benchmark.rb]
  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = %w[README.md]

  spec.required_ruby_version = ">= 4.0"
  spec.add_dependency "pg", "~> 1.6.3"
end
