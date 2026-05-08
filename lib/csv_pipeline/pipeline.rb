# frozen_string_literal: true

module CsvPipeline
  class Pipeline
    VALID_ON_ERROR_VALUES = %i[continue stop].freeze

    def self.define_policy(name, &factory)
      PolicyRegistry.define(name, &factory)
    end

    def initialize(on_error: :continue, &block)
      unless VALID_ON_ERROR_VALUES.include?(on_error)
        raise ArgumentError,
              "on_error must be :continue or :stop, got #{on_error.inspect}"
      end

      @fields     = []
      @header_map = nil
      @on_error   = on_error
      instance_eval(&block) if block
    end

    def field(name)
      f = Field.new(name)
      @fields << f
      f
    end

    def header_map(mapping)
      @header_map = mapping
    end

    def process(csv_path)
      results = []
      if @header_map
        positional = @header_map.values.all? { |v| v.is_a?(Integer) }
        if positional
          CSV.foreach(csv_path) do |row|
            append_result(@header_map.transform_values { |idx| row[idx] }, results)
          end
        else
          CSV.foreach(csv_path, headers: true) do |row|
            append_result(@header_map.transform_values { |raw| row[raw] }, results)
          end
        end
      else
        CSV.foreach(csv_path, headers: true, header_converters: :symbol) do |row|
          append_result(row.to_h, results)
        end
      end
      results
    end

    private

    def append_result(record, results)
      all_errors = []
      @fields.each { |f| all_errors.concat(f.process(record, on_error: @on_error)) }
      results << Result.new(record: record, errors: all_errors)
    end
  end
end
