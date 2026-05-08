# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Pipeline#header_map" do
  def write_csv(content)
    Tempfile.new(["test", ".csv"]).tap do |f|
      f.write(content)
      f.rewind
    end
  end

  describe "string header mapping" do
    let(:csv) { write_csv("Full Name,E-Mail\nAlice,alice@example.com\nBob,bob@example.com\n") }

    it "maps raw header names to friendly symbols" do
      pipeline = Pipeline.new do
        header_map(name: "Full Name", email: "E-Mail")
        field(:name).present
        field(:email).present
      end
      result = pipeline.process(csv.path).first
      expect(result.record[:name]).to eq("Alice")
      expect(result.record[:email]).to eq("alice@example.com")
    end

    it "maps headers containing spaces and special characters" do
      csv2 = write_csv("\"Height (cm)\",\"Weight (kg)\"\n188.0,77.1\n")
      pipeline = Pipeline.new do
        header_map(height_cm: "Height (cm)", weight_kg: "Weight (kg)")
        field(:height_cm).present
      end
      result = pipeline.process(csv2.path).first
      expect(result.record[:height_cm]).to eq("188.0")
      expect(result.record[:weight_kg]).to eq("77.1")
    end

    it "applies field policies to remapped values" do
      pipeline = Pipeline.new do
        header_map(name: "Full Name")
        field(:name).present
      end
      blank_csv = write_csv("Full Name\n\n")
      result = pipeline.process(blank_csv.path).first
      expect(result).not_to be_valid
      expect(result.errors.first[:field]).to eq(:name)
    end
  end

  describe "positional (headerless) mapping" do
    let(:csv) { write_csv("Alice,alice@example.com,30\nBob,bob@example.com,17\n") }

    it "maps column indices to friendly symbols" do
      pipeline = Pipeline.new do
        header_map(name: 0, email: 1, age: 2)
        field(:name).present
      end
      result = pipeline.process(csv.path).first
      expect(result.record[:name]).to eq("Alice")
      expect(result.record[:email]).to eq("alice@example.com")
      expect(result.record[:age]).to eq("30")
    end

    it "returns one result per row" do
      pipeline = Pipeline.new do
        header_map(name: 0)
        field(:name).present
      end
      expect(pipeline.process(csv.path).length).to eq(2)
    end

    it "applies field policies to positional values" do
      pipeline = Pipeline.new do
        header_map(name: 0)
        field(:name).present
      end
      blank_csv = write_csv(",alice@example.com\n")
      result = pipeline.process(blank_csv.path).first
      expect(result).not_to be_valid
    end
  end

  describe "without header_map" do
    it "default behavior unchanged (header_converters: :symbol)" do
      csv = write_csv("name,email\nAlice,alice@example.com\n")
      pipeline = Pipeline.new { field(:name).present }
      result = pipeline.process(csv.path).first
      expect(result.record[:name]).to eq("Alice")
    end
  end
end
