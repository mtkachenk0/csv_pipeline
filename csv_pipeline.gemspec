# frozen_string_literal: true

require_relative "lib/csv_pipeline/version"

Gem::Specification.new do |spec|
  spec.name          = "csv_pipeline"
  spec.version       = CsvPipeline::VERSION
  spec.authors       = ["Maxim Tkachenko"]
  spec.summary       = "Configurable CSV processing pipeline with composable policies"
  spec.files         = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
