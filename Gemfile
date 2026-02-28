# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Pin bigdecimal to use the default gem bundled with Ruby (avoids native ext compilation)
gem "bigdecimal", "1.4.1" if RUBY_VERSION < "3.0"

group :development, :test do
  gem "rake", "~> 13.0"
  gem "rantly", "~> 2.0"
  gem "rspec", "~> 3.12"
  gem "webmock", "~> 3.26.1"
end
