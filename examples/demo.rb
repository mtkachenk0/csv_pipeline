# frozen_string_literal: true

require_relative "../lib/csv_pipeline"

EMAIL_REGEXP = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

# Custom policy — no library changes needed
Pipeline.define_policy(:min_length) do |min|
  validate { |_key, value, _payload| value.to_s.length >= min }
  message  { |key, _value, _payload| "#{key} must be at least #{min} characters" }
end

pipeline = Pipeline.new do
  field(:email).normalize_email.present.format(EMAIL_REGEXP)
  field(:name).present.apply(:min_length, 2)
  field(:age).default("unknown")
end

puts "Processing sample.csv\n\n"

pipeline.process(File.expand_path("sample.csv", __dir__)).each_with_index do |result, i|
  row = i + 2
  if result.valid?
    puts "Row #{row} OK    #{result.record}"
  else
    msgs = result.errors.map { |e| "#{e[:field]}: #{e[:message]}" }.join(" | ")
    puts "Row #{row} ERROR #{msgs}"
    puts "       record: #{result.record}"
  end
end
