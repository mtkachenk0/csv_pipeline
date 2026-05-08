# frozen_string_literal: true

require "spec_helper"

RSpec.describe CsvPipeline::PolicyRegistry do
  before { described_class.reset! }

  describe ".define and .fetch" do
    it "stores and retrieves a no-arg policy" do
      described_class.define(:shout) do
        transform { |_k, v, _p| v.to_s.upcase }
      end
      policy = described_class.fetch(:shout)
      expect(policy.transform(:x, "hello", {})).to eq("HELLO")
    end

    it "passes args to the factory block" do
      described_class.define(:prepend) do |prefix|
        transform { |_k, v, _p| "#{prefix}#{v}" }
      end
      policy = described_class.fetch(:prepend, ">>")
      expect(policy.transform(:x, "hello", {})).to eq(">>hello")
    end

    it "each fetch call returns a new Policy instance" do
      described_class.define(:noop) {}
      p1 = described_class.fetch(:noop)
      p2 = described_class.fetch(:noop)
      expect(p1).not_to be(p2)
    end

    it "raises KeyError for unknown policy" do
      expect { described_class.fetch(:unknown) }
        .to raise_error(KeyError, /unknown/)
    end

    it "raises ArgumentError when defining a policy with a duplicate name" do
      described_class.define(:shout) { transform { |_k, v, _p| v.upcase } }
      expect { described_class.define(:shout) { transform { |_k, v, _p| v.downcase } } }
        .to raise_error(ArgumentError, /shout/)
    end

    it "does not overwrite the original policy when duplicate is attempted" do
      described_class.define(:shout) { transform { |_k, v, _p| v.upcase } }
      described_class.define(:shout) { transform { |_k, v, _p| v.downcase } } rescue nil
      expect(described_class.fetch(:shout).transform(:x, "Hello", {})).to eq("HELLO")
    end
  end

  describe ".reset!" do
    it "clears all registered policies" do
      described_class.define(:temp) { transform { |_k, v, _p| v } }
      described_class.reset!
      expect { described_class.fetch(:temp) }.to raise_error(KeyError)
    end
  end
end
