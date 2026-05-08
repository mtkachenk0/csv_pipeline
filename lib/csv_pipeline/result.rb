# frozen_string_literal: true

module CsvPipeline
  class Result
    attr_reader :record, :errors

    def initialize(record:, errors:)
      @record = record
      @errors = errors.freeze
    end

    def valid?
      @errors.empty?
    end
  end
end
