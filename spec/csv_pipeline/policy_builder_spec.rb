# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CsvPipeline::PolicyBuilder do
  subject(:builder) { described_class.new }

  describe '#build' do
    it 'builds a Policy with no-op defaults when no blocks set' do
      policy = builder.build
      expect(policy).to be_a(CsvPipeline::Policy)
      expect(policy.eligible?(:k, 'v', {})).to be true
      expect(policy.transform(:k, 'v', {})).to eq('v')
      expect(policy.valid?(:k, 'v',   {})).to be true
      expect(policy.message(:k, 'v',  {})).to be_nil
    end

    it 'captures and uses transform block' do
      builder.transform { |_k, v, _p| v.upcase }
      expect(builder.build.transform(:k, 'hi', {})).to eq('HI')
    end

    it 'captures and uses validate block' do
      builder.validate { |_k, v, _p| v != '' }
      expect(builder.build.valid?(:k, '',  {})).to be false
      expect(builder.build.valid?(:k, 'x', {})).to be true
    end

    it 'captures and uses eligible block' do
      builder.eligible { |_k, v, _p| v.nil? }
      expect(builder.build.eligible?(:k, nil, {})).to be true
      expect(builder.build.eligible?(:k, 'x', {})).to be false
    end

    it 'captures and uses message block' do
      builder.message { |k, _v, _p| "#{k} is required" }
      expect(builder.build.message(:name, '', {})).to eq('name is required')
    end
  end
end
