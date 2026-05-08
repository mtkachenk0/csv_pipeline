# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CsvPipeline::Field do
  before do
    CsvPipeline::PolicyRegistry.reset!
    CsvPipeline::Pipeline.define_policy(:upcase_t) do
      transform { |_k, v, _p| v.to_s.upcase }
    end
    CsvPipeline::Pipeline.define_policy(:no_digits) do
      validate { |_k, v, _p| !v.to_s.match?(/\d/) }
      message  { |k, _v, _p| "#{k} must not contain digits" }
    end
    CsvPipeline::Pipeline.define_policy(:skip_blank) do
      eligible  { |_k, v, _p| !v.to_s.strip.empty? }
      validate  { |_k, v, _p| v.length > 2 }
      message   { |k, _v, _p| "#{k} is too short" }
    end
    CsvPipeline::Pipeline.define_policy(:check_lower) do
      validate { |_k, v, _p| v == v.downcase }
      message  { |k, _v, _p| "#{k} must be lowercase" }
    end
    CsvPipeline::Pipeline.define_policy(:raises_on_transform) do
      transform { |_k, _v, _p| raise ZeroDivisionError, 'divided by 0' }
    end
    CsvPipeline::Pipeline.define_policy(:raises_on_eligible) do
      eligible { |_k, _v, _p| raise 'eligible blew up' }
    end
    CsvPipeline::Pipeline.define_policy(:raises_on_validate) do
      validate { |_k, _v, _p| raise ArgumentError, 'validate blew up' }
    end
    CsvPipeline::Pipeline.define_policy(:raises_on_message) do
      validate { |_k, _v, _p| false }
      message  { |_k, _v, _p| raise TypeError, 'message blew up' }
    end
    CsvPipeline::Pipeline.define_policy(:safe_policy) do
      validate { |_k, v, _p| v == 'safe' }
      message  { |k, _v, _p| "#{k} not safe" }
    end
  end

  subject(:field) { described_class.new(:email) }

  describe '#apply' do
    it 'returns self for chaining' do
      expect(field.apply(:upcase_t)).to be(field)
    end

    it 'appends one policy per call' do
      field.apply(:upcase_t).apply(:no_digits)
      expect(field.policies.length).to eq(2)
    end

    it 'raises KeyError for unknown policy name' do
      expect { field.apply(:nonexistent) }.to raise_error(KeyError)
    end
  end

  describe '#process' do
    it 'mutates record field value via transform' do
      record = { email: 'hello' }
      field.apply(:upcase_t).process(record)
      expect(record[:email]).to eq('HELLO')
    end

    it 'collects validation errors without stopping' do
      record = { email: 'abc123' }
      errors = field.apply(:no_digits).process(record)
      expect(errors).to eq([{ field: :email, message: 'email must not contain digits' }])
    end

    it 'collects multiple errors across policies on same field' do
      record = { email: 'a1' }
      errors = field.apply(:no_digits).apply(:skip_blank).process(record)
      expect(errors.length).to eq(2)
    end

    it 'skips policy entirely when eligible? returns false' do
      record = { email: '' }
      errors = field.apply(:skip_blank).process(record)
      expect(errors).to be_empty
    end

    it 'runs transform before validate on the same field' do
      record = { email: 'hello' }
      errors = field.apply(:upcase_t).apply(:check_lower).process(record)
      expect(errors).to eq([{ field: :email, message: 'email must be lowercase' }])
    end

    it 'passes the full record as payload' do
      CsvPipeline::Pipeline.define_policy(:uses_payload) do
        transform { |_k, _v, payload| payload[:other].to_s.reverse }
      end
      record = { email: 'ignored', other: 'abc' }
      described_class.new(:email).apply(:uses_payload).process(record)
      expect(record[:email]).to eq('cba')
    end
  end

  describe 'error handling' do
    it 'catches raising transform — error has :exception key and message format' do
      record = { email: 'test@example.com' }
      errors = field.apply(:raises_on_transform).process(record)
      expect(errors.length).to eq(1)
      expect(errors.first[:field]).to eq(:email)
      expect(errors.first[:message]).to eq('ZeroDivisionError: divided by 0')
      expect(errors.first[:exception]).to be_a(ZeroDivisionError)
    end

    it 'catches raising eligible block' do
      record = { email: 'test@example.com' }
      errors = field.apply(:raises_on_eligible).process(record)
      expect(errors.length).to eq(1)
      expect(errors.first[:exception]).to be_a(RuntimeError)
    end

    it 'catches raising validate block' do
      record = { email: 'test@example.com' }
      errors = field.apply(:raises_on_validate).process(record)
      expect(errors.length).to eq(1)
      expect(errors.first[:exception]).to be_a(ArgumentError)
    end

    it 'catches raising message block' do
      record = { email: 'test@example.com' }
      errors = field.apply(:raises_on_message).process(record)
      expect(errors.length).to eq(1)
      expect(errors.first[:exception]).to be_a(TypeError)
    end

    it 'continues to next policy by default after error' do
      record = { email: 'not_safe' }
      errors = field.apply(:raises_on_transform).apply(:safe_policy).process(record)
      expect(errors.length).to eq(2)
      expect(errors.first[:exception]).to be_a(ZeroDivisionError)
      expect(errors.last[:message]).to eq('email not safe')
    end

    it 'stops at erroring policy when on_error: :stop' do
      record = { email: 'not_safe' }
      errors = field.apply(:raises_on_transform).apply(:safe_policy).process(record, on_error: :stop)
      expect(errors.length).to eq(1)
      expect(errors.first[:exception]).to be_a(ZeroDivisionError)
    end
  end
end
