# frozen_string_literal: true

require "spec_helper"

EMAIL_REGEXP = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

RSpec.describe "CSV Pipeline integration" do
  let(:csv_path) { File.expand_path("../../examples/sample.csv", __dir__) }

  let(:pipeline) do
    Pipeline.new do
      field(:email).normalize_email.present.format(EMAIL_REGEXP)
      field(:name).present
      field(:age).default("unknown")
    end
  end

  it "returns one result per CSV data row" do
    expect(pipeline.process(csv_path).length).to eq(25)
  end

  context "row 1 — Alex, valid email, age 41" do
    subject(:result) { pipeline.process(csv_path)[0] }

    it { is_expected.to be_valid }

    it "preserves correct values" do
      expect(result.record[:name]).to eq("Alex")
      expect(result.record[:email]).to eq("email1@test.com")
      expect(result.record[:age]).to eq("41")
    end
  end

  context "row 19 — comment line parsed as data, nil email" do
    subject(:result) { pipeline.process(csv_path)[18] }

    it { is_expected.not_to be_valid }

    it "does not stop on first error" do
      expect(result.errors.length).to be >= 2
    end

    it "collects multiple errors on email field" do
      error_fields = result.errors.map { |e| e[:field] }
      expect(error_fields.count(:email)).to be >= 2
    end

    it "applies default to nil age" do
      expect(result.record[:age]).to eq("unknown")
    end
  end

  context "row 20 — nil name, valid email" do
    subject(:result) { pipeline.process(csv_path)[19] }

    it { is_expected.not_to be_valid }

    it "reports name error" do
      error_fields = result.errors.map { |e| e[:field] }
      expect(error_fields).to include(:name)
    end
  end

  context "row 25 — Judy, invalid email format" do
    subject(:result) { pipeline.process(csv_path)[24] }

    it { is_expected.not_to be_valid }

    it "reports email error" do
      error_fields = result.errors.map { |e| e[:field] }
      expect(error_fields).to include(:email)
    end
  end

  context "custom policy without modifying library code" do
    it "works end-to-end" do
      Pipeline.define_policy(:min_length) do |min|
        validate { |_k, v, _p| v.to_s.length >= min }
        message  { |key, _v, _p| "#{key} is too short (min #{min})" }
      end

      custom = Pipeline.new { field(:name).apply(:min_length, 4) }
      results = custom.process(csv_path)

      alex = results.find { |r| r.record[:name] == "Alex" }
      jim  = results.find { |r| r.record[:name] == "Jim" }

      expect(alex.valid?).to be true
      expect(jim.valid?).to be false
      expect(jim.errors.first[:message]).to include("too short")
    end
  end

  context "eligible block as conditional guard" do
    it "skips policy when record does not match condition" do
      Pipeline.define_policy(:vip_email) do
        eligible { |_k, _v, payload| payload[:subscribed] == "T" }
        validate { |_k, v, _p| v.to_s.end_with?(".com") }
        message  { |k, _v, _p| "#{k} must end with .com for subscribers" }
      end

      p = Pipeline.new { field(:email).apply(:vip_email) }
      results = p.process(csv_path)

      judy = results.find { |r| r.record[:name] == "Judy" }
      expect(judy.valid?).to be true
    end
  end

  context "default with callable fill" do
    it "evaluates proc per row, not at definition time" do
      call_count = 0
      field = CsvPipeline::Field.new(:status)
      field.apply(:default, -> { call_count += 1; "computed_#{call_count}" })

      r1 = { status: "" }
      r2 = { status: "" }
      r3 = { status: "" }
      field.process(r1)
      field.process(r2)
      field.process(r3)

      expect(r1[:status]).to eq("computed_1")
      expect(r2[:status]).to eq("computed_2")
      expect(r3[:status]).to eq("computed_3")
    end

    it "static value still works unchanged" do
      pipeline = Pipeline.new { field(:age).default("fallback") }
      results  = pipeline.process(csv_path)
      blank_age_result = results.find { |r| r.record[:age] == "fallback" }
      expect(blank_age_result).not_to be_nil
    end
  end

  context "edge cases with inline CSV content" do
    def pipeline_for(*fields)
      Pipeline.new do
        fields.each { |f| field(f) }
      end
    end

    def with_csv(content)
      require "tempfile"
      f = Tempfile.new(["edge", ".csv"])
      f.write(content)
      f.flush
      yield f.path
    ensure
      f.close
      f.unlink
    end

    it "returns empty array for headers-only file (zero data rows)" do
      with_csv("name,email\n") do |path|
        results = pipeline_for(:name, :email).process(path)
        expect(results).to eq([])
      end
    end

    it "returns empty array for completely empty file" do
      with_csv("") do |path|
        results = pipeline_for(:name).process(path)
        expect(results).to eq([])
      end
    end

    it "parses quoted fields containing commas as a single value" do
      with_csv("name,role\n\"Smith, Jr.\",admin\n") do |path|
        results = pipeline_for(:name, :role).process(path)
        expect(results.length).to eq(1)
        expect(results.first.record[:name]).to eq("Smith, Jr.")
      end
    end

    it "passes UTF-8 multi-byte characters through unchanged" do
      with_csv("name,city\nAndré,北京\ncafé,Zürich\n") do |path|
        results = pipeline_for(:name, :city).process(path)
        expect(results.length).to eq(2)
        expect(results[0].record[:name]).to eq("André")
        expect(results[0].record[:city]).to eq("北京")
        expect(results[1].record[:name]).to eq("café")
        expect(results[1].record[:city]).to eq("Zürich")
      end
    end
  end

  context "payload access for cross-field logic" do
    it "skips validation when guard field is blank" do
      Pipeline.define_policy(:required_when_named) do
        eligible { |_k, _v, payload| !payload[:name].to_s.strip.empty? }
        validate { |_k, v, _p| !v.to_s.strip.empty? }
        message  { |k, _v, _p| "#{k} required when name is present" }
      end

      field = CsvPipeline::Field.new(:email)
      field.apply(:required_when_named)

      record_with_name    = { name: "Alice", email: "" }
      record_without_name = { name: "",      email: "" }

      expect(field.process(record_with_name)).not_to be_empty
      expect(field.process(record_without_name)).to be_empty
    end
  end
end
