# frozen_string_literal: true

require_relative "lib/tickrb/version"

Gem::Specification.new do |spec|
  spec.name = "tickrb"
  spec.version = Tickrb::VERSION
  spec.authors = ["Graham Turner"]
  spec.email = ["turnertgraham@gmail.com"]

  spec.summary = "A Ruby gem for tickrb functionality"
  spec.description = "Longer description of what tickrb does"
  spec.homepage = "https://github.com/tgturner/tickrb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tgturner/tickrb"
  spec.metadata["changelog_uri"] = "https://github.com/tgturner/tickrb/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "webrick"
  spec.add_dependency "sorbet-runtime"
  spec.add_dependency "net-http"
  spec.add_dependency "uri"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "sorbet", "~> 0.5"
  spec.add_development_dependency "tapioca"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "rspec-sorbet-types"
  spec.add_development_dependency "dotenv"
end
