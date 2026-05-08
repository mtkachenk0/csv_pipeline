# frozen_string_literal: true

require "spec_helper"

RSpec.describe CsvPipeline::Pipeline do
  before { CsvPipeline::PolicyRegistry.reset! }

  describe ".define_policy" do
    it "registers a policy accessible by name" do
      described_class.define_policy(:shout) do
        transform { |_k, v, _p| v.to_s.upcase }
      end
      policy = CsvPipeline::PolicyRegistry.fetch(:shout)
      expect(policy.transform(:x, "hi", {})).to eq("HI")
    end
  end

  describe "#field" do
    before do
      described_class.define_policy(:noop) { transform { |_k, v, _p| v } }
    end

    it "allows chaining policies on the returned field" do
      expect {
        described_class.new { field(:name).apply(:noop) }
      }.not_to raise_error
    end
  end

  describe "#process" do
    let(:csv_path) { File.expand_path("../../examples/sample.csv", __dir__) }

    before do
      described_class.define_policy(:present) do
        validate { |_k, v, _p| !v.to_s.strip.empty? }
        message  { |k, _v, _p| "#{k} can't be blank" }
      end
    end

    it "returns one Result per CSV data row" do
      pipeline = described_class.new { field(:name).present }
      results  = pipeline.process(csv_path)
      expect(results.length).to eq(25)
    end

    it "returns Result objects" do
      pipeline = described_class.new { field(:name) }
      results  = pipeline.process(csv_path)
      expect(results).to all(be_a(CsvPipeline::Result))
    end

    it "does not modify the original CSV source data" do
      described_class.define_policy(:upcase) do
        transform { |_k, v, _p| v.to_s.upcase }
      end

      pipeline = described_class.new { field(:name).apply(:upcase) }
      results  = pipeline.process(csv_path)

      expect(results.first.record[:name]).to eq("ALEX")

      raw = CSV.read(csv_path, headers: true).first
      expect(raw["Name"]).to eq("Alex")
    end

    it "accumulates errors from all fields without stopping" do
      described_class.define_policy(:always_fail) do
        validate { |_k, _v, _p| false }
        message  { |k, _v, _p| "#{k} always fails" }
      end
      pipeline = described_class.new do
        field(:name).apply(:always_fail)
        field(:email).apply(:always_fail)
      end
      result = pipeline.process(csv_path).first
      expect(result.errors.length).to eq(2)
    end
  end

  describe "on_error: option" do
    before do
      CsvPipeline::Pipeline.define_policy(:raises_transform) do
        transform { |_k, _v, _p| raise RuntimeError, "boom" }
      end
      CsvPipeline::Pipeline.define_policy(:always_invalid) do
        validate { |_k, _v, _p| false }
        message  { |k, _v, _p| "#{k} always fails" }
      end
    end

    it "raises ArgumentError for unknown on_error value" do
      expect { CsvPipeline::Pipeline.new(on_error: :explode) {} }.to raise_error(ArgumentError, /on_error/)
    end

    it "defaults to :continue — second policy error collected after first raises" do
      require "tempfile"
      csv = Tempfile.new(["test", ".csv"])
      csv.write("email\ntest@example.com\n")
      csv.flush

      pipeline = CsvPipeline::Pipeline.new do
        field(:email).apply(:raises_transform).apply(:always_invalid)
      end

      results = pipeline.process(csv.path)
      errors = results.first.errors
      expect(errors.length).to eq(2)
      expect(errors.first[:exception]).to be_a(RuntimeError)
      expect(errors.last[:message]).to eq("email always fails")
    ensure
      csv.close
      csv.unlink
    end

    it "propagates on_error: :stop — stops after first raising policy" do
      require "tempfile"
      csv = Tempfile.new(["test", ".csv"])
      csv.write("email\ntest@example.com\n")
      csv.flush

      pipeline = CsvPipeline::Pipeline.new(on_error: :stop) do
        field(:email).apply(:raises_transform).apply(:always_invalid)
      end

      results = pipeline.process(csv.path)
      errors = results.first.errors
      expect(errors.length).to eq(1)
      expect(errors.first[:exception]).to be_a(RuntimeError)
    ensure
      csv.close
      csv.unlink
    end
  end
end
