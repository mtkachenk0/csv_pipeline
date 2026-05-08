# frozen_string_literal: true

module CsvPipeline
  class Pipeline
    def self.define_policy(name, &factory)
      PolicyRegistry.define(name, &factory)
    end

    def initialize(&block)
      @fields     = []
      @header_map = nil
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
      @fields.each { |f| all_errors.concat(f.process(record)) }
      results << Result.new(record: record, errors: all_errors)
    end
  end
end
