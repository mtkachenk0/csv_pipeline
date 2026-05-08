# frozen_string_literal: true

require "spec_helper"

RSpec.describe CsvPipeline::Policy do
  describe "#eligible?" do
    it "returns true when no eligible block given" do
      expect(described_class.new.eligible?(:name, "v", {})).to be true
    end

    it "evaluates block with key, value, payload" do
      policy = described_class.new(eligible: ->(_k, v, _p) { v.to_s.empty? })
      expect(policy.eligible?(:x, "",  {})).to be true
      expect(policy.eligible?(:x, "v", {})).to be false
    end
  end

  describe "#transform" do
    it "returns value unchanged when no transform block" do
      expect(described_class.new.transform(:name, "hello", {})).to eq("hello")
    end

    it "applies block with key, value, payload" do
      policy = described_class.new(transform: ->(_k, v, _p) { v.upcase })
      expect(policy.transform(:name, "hello", {})).to eq("HELLO")
    end

    it "can use payload for cross-field transforms" do
      policy = described_class.new(transform: ->(_k, v, p) { p[:prefix].to_s + v.to_s })
      expect(policy.transform(:slug, "foo", { prefix: "pre_" })).to eq("pre_foo")
    end
  end

  describe "#valid?" do
    it "returns true when no validate block" do
      expect(described_class.new.valid?(:name, "anything", {})).to be true
    end

    it "evaluates block returning boolean" do
      policy = described_class.new(validate: ->(_k, v, _p) { v.length > 3 })
      expect(policy.valid?(:name, "hi",    {})).to be false
      expect(policy.valid?(:name, "hello", {})).to be true
    end
  end

  describe "#message" do
    it "returns nil when no message block" do
      expect(described_class.new.message(:name, "val", {})).to be_nil
    end

    it "evaluates block with key, value, payload" do
      policy = described_class.new(message: ->(key, _v, _p) { "#{key} is bad" })
      expect(policy.message(:email, "x", {})).to eq("email is bad")
    end
  end
end
