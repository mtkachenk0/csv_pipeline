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
    expect(pipeline.process(csv_path).length).to eq(5)
  end

  context "row 1 — Alice, valid email, age 30" do
    subject(:result) { pipeline.process(csv_path)[0] }

    it { is_expected.to be_valid }

    it "preserves correct values" do
      expect(result.record[:name]).to eq("Alice")
      expect(result.record[:email]).to eq("alice@example.com")
      expect(result.record[:age]).to eq("30")
    end
  end

  context "row 2 — Bob, uppercase email, age 17" do
    subject(:result) { pipeline.process(csv_path)[1] }

    it { is_expected.to be_valid }

    it "normalizes email to lowercase" do
      expect(result.record[:email]).to eq("bob@example.com")
    end
  end

  context "row 3 — blank name, invalid email, blank age" do
    subject(:result) { pipeline.process(csv_path)[2] }

    it { is_expected.not_to be_valid }

    it "collects errors for both name and email" do
      error_fields = result.errors.map { |e| e[:field] }
      expect(error_fields).to include(:name, :email)
    end

    it "does not stop on first error" do
      expect(result.errors.length).to be >= 2
    end

    it "applies default to blank age" do
      expect(result.record[:age]).to eq("unknown")
    end
  end

  context "row 4 — Charlie, valid email, blank age" do
    subject(:result) { pipeline.process(csv_path)[3] }

    it { is_expected.to be_valid }

    it "applies default to blank age" do
      expect(result.record[:age]).to eq("unknown")
    end
  end

  context "row 5 — blank name, whitespace-only email" do
    subject(:result) { pipeline.process(csv_path)[4] }

    it { is_expected.not_to be_valid }

    it "reports errors for name and email" do
      error_fields = result.errors.map { |e| e[:field] }
      expect(error_fields).to include(:name, :email)
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

      alice   = results.find { |r| r.record[:name] == "Alice" }
      bob     = results.find { |r| r.record[:name] == "Bob" }
      charlie = results.find { |r| r.record[:name] == "Charlie" }

      expect(alice.valid?).to be true
      expect(bob.valid?).to be false
      expect(charlie.valid?).to be true
      expect(bob.errors.first[:message]).to include("too short")
    end
  end

  context "eligible block as conditional guard" do
    it "skips policy when record does not match condition" do
      Pipeline.define_policy(:vip_email) do
        eligible { |_k, _v, payload| payload[:age].to_i >= 18 }
        validate { |_k, v, _p| v.to_s.end_with?(".com") }
        message  { |k, _v, _p| "#{k} must end with .com for adults" }
      end

      p = Pipeline.new { field(:email).apply(:vip_email) }
      results = p.process(csv_path)

      bob = results.find { |r| r.record[:name] == "Bob" }
      expect(bob.valid?).to be true
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
