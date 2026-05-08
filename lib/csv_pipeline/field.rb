# frozen_string_literal: true

module CsvPipeline
  class Field
    attr_reader :name, :policies

    def initialize(name)
      @name = name.to_sym
      @policies = []
    end

    def apply(policy_name, *args)
      @policies << PolicyRegistry.fetch(policy_name, *args)
      self
    end

    def present = apply(:present)

    def email = apply(:email)

    def format(regexp) = apply(:format, regexp)

    def default(value) = apply(:default, value)

    def process(record, on_error: :continue)
      errors = []
      @policies.each do |policy|
        begin
          value = record[@name]
          next unless policy.eligible?(@name, value, record)

          record[@name] = policy.transform(@name, value, record)
          value = record[@name]
          unless policy.valid?(@name, value, record)
            errors << { field: @name, message: policy.message(@name, value, record) }
          end
        rescue StandardError => e
          errors << { field: @name, message: "#{e.class}: #{e.message}", exception: e }
          break if on_error == :stop
        end
      end
      errors
    end
  end
end
