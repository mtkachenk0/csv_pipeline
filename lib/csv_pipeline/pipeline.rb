# frozen_string_literal: true

module CsvPipeline
  class Pipeline
    def self.define_policy(name, &factory)
      PolicyRegistry.define(name, &factory)
    end
  end
end
