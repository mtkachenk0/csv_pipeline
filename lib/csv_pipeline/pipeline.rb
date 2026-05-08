# frozen_string_literal: true

module CsvPipeline
  class Pipeline
    def self.define_policy(name, &factory)
      PolicyRegistry.define(name, &factory)
    end

    def initialize(&block)
      @fields = []
      instance_eval(&block) if block
    end

    def field(name)
      f = Field.new(name)
      @fields << f
      f
    end

    def process(csv_path)
      results = []
      CSV.foreach(csv_path, headers: true, header_converters: :symbol) do |row|
        record     = row.to_h
        all_errors = []
        @fields.each { |f| all_errors.concat(f.process(record)) }
        results << Result.new(record: record, errors: all_errors)
      end
      results
    end
  end
end
