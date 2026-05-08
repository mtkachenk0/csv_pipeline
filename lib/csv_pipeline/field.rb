# frozen_string_literal: true

module CsvPipeline
  class Field
    attr_reader :name, :policies

    def initialize(name)
      @name     = name.to_sym
      @policies = []
    end

    def apply(policy_name, *args)
      @policies << PolicyRegistry.fetch(policy_name, *args)
      self
    end

    def present         = apply(:present)
    def normalize_email = apply(:normalize_email)
    def format(regexp)  = apply(:format, regexp)
    def default(value)  = apply(:default, value)

    def process(record)
      errors = []
      @policies.each do |policy|
        value = record[@name]
        next unless policy.eligible?(@name, value, record)
        record[@name] = policy.transform(@name, value, record)
        value = record[@name]
        unless policy.valid?(@name, value, record)
          errors << { field: @name, message: policy.message(@name, value, record) }
        end
      end
      errors
    end
  end
end
