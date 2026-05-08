# frozen_string_literal: true

require "spec_helper"

RSpec.describe CsvPipeline::Result do
  describe "#valid?" do
    it "is true when errors is empty" do
      result = described_class.new(record: { name: "Alice" }, errors: [])
      expect(result.valid?).to be true
    end

    it "is false when errors present" do
      result = described_class.new(
        record: { name: "" },
        errors: [{ field: :name, message: "can't be blank" }]
      )
      expect(result.valid?).to be false
    end
  end

  describe "attributes" do
    let(:record) { { name: "Bob", email: "bob@example.com" } }
    let(:errors) { [{ field: :age, message: "can't be blank" }] }
    subject(:result) { described_class.new(record: record, errors: errors) }

    it "exposes record" do
      expect(result.record).to eq({ name: "Bob", email: "bob@example.com" })
    end

    it "exposes errors" do
      expect(result.errors).to eq([{ field: :age, message: "can't be blank" }])
    end
  end
end
