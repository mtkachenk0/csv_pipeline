# frozen_string_literal: true

module CsvPipeline
  module BuiltInPolicies
    def self.register!
      Pipeline.define_policy(:present) do
        validate { |_key, value, _payload| !value.to_s.strip.empty? }
        message  { |key, _value, _payload| "#{key} can't be blank" }
      end

      Pipeline.define_policy(:format) do |regexp|
        validate { |_key, value, _payload| value.to_s.match?(regexp) }
        message  { |key, _value, _payload| "#{key} has invalid format" }
      end

      Pipeline.define_policy(:default) do |fill|
        eligible  { |_key, value, _payload| value.to_s.strip.empty? }
        transform { |_key, _value, _payload| fill.respond_to?(:call) ? fill.call : fill }
      end

      Pipeline.define_policy(:email) do
        transform { |_key, value, _payload| value.to_s.downcase.strip }
      end
    end
  end
end
