# frozen_string_literal: true

module CsvPipeline
  class PolicyDefinition
    def initialize(&factory)
      @factory = factory
    end

    def instantiate(*args)
      builder = PolicyBuilder.new
      builder.instance_exec(*args, &@factory)
      builder.build
    end
  end
end
