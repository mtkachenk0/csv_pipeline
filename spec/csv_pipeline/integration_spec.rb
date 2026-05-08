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
