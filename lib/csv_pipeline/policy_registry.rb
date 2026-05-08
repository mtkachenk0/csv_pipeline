# frozen_string_literal: true

module CsvPipeline
  module PolicyRegistry
    @policies = {}

    def self.define(name, &factory)
      @policies[name.to_sym] = PolicyDefinition.new(&factory)
    end

    def self.fetch(name, *args)
      key = name.to_sym
      raise KeyError, "Unknown policy: #{key.inspect}" unless @policies.key?(key)
      @policies[key].instantiate(*args)
    end

    def self.reset!
      @policies = {}
    end
  end
end
