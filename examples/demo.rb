require_relative "lib/csv_pipeline"

EMAIL_REGEXP = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
SEX_REGEXP   = /\A(M|F)\z/

Pipeline.define_policy(:positive_number) do
  validate { |_k, v, _p| v.to_s.match?(/\A\d+(\.\d+)?\z/) && v.to_f > 0 }
  message  { |k, _v, _p| "#{k} must be a positive number" }
end

Pipeline.define_policy(:positive_integer) do
  validate { |_k, v, _p| v.to_s.match?(/\A\d+\z/) && v.to_i > 0 }
  message  { |k, _v, _p| "#{k} must be a positive integer" }
end

pipeline = Pipeline.new do
  header_map(
    name:       "Name",
    sex:        "Sex",
    age:        "Age",
    height_cm:  "Height (cm)",
    weight_kg:  "Weight (kg)",
    email:      "Email",
    subscribed: "Subscribed"
  )

  field(:name).present
  field(:sex).present.format(SEX_REGEXP)
  field(:age).present.apply(:positive_integer)
  field(:height_cm).present.apply(:positive_number)
  field(:weight_kg).present.apply(:positive_number)
  field(:email).normalize_email.present.format(EMAIL_REGEXP)
  field(:subscribed).default("F")
end

csv_path = File.expand_path("examples/biostats.csv", __dir__)
results  = pipeline.process(csv_path)

valid_count   = results.count(&:valid?)
invalid_count = results.reject(&:valid?).count

puts "Processed #{results.length} rows — #{valid_count} valid, #{invalid_count} invalid"
puts

results.each_with_index do |result, i|
  name = result.record[:name].to_s
  if result.valid?
    r = result.record
    puts "[row #{i + 2}] OK      #{name.ljust(6)} sex=#{r[:sex]} age=#{r[:age]} sub=#{r[:subscribed]}"
  else
    puts "[row #{i + 2}] INVALID #{name.inspect}"
    result.errors.each { |e| puts "         #{e[:field]}: #{e[:message]}" }
  end
end
