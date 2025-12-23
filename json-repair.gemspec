# frozen_string_literal: true

require_relative 'lib/json/repair/version'

Gem::Specification.new do |spec|
  spec.name = 'json-repair'
  spec.version = JSON::Repair::VERSION
  spec.authors = ['Aleksandr Zykov']
  spec.email = ['alexandrz@gmail.com']

  spec.summary = 'Repairs broken JSON strings.'
  spec.description = 'This is a simple gem that repairs broken JSON strings.'
  spec.homepage = 'https://github.com/sashazykov/json-repair-rb'
  spec.license = 'ISC'
  spec.required_ruby_version = '>= 2.7.8'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
end
