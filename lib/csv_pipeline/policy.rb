# frozen_string_literal: true

module CsvPipeline
  class Policy
    def initialize(transform: nil, validate: nil, eligible: nil, message: nil)
      @transform_block = transform
      @validate_block  = validate
      @eligible_block  = eligible
      @message_block   = message
    end

    def eligible?(key, value, payload)
      return true unless @eligible_block
      @eligible_block.call(key, value, payload)
    end

    def transform(key, value, payload)
      return value unless @transform_block
      @transform_block.call(key, value, payload)
    end

    def valid?(key, value, payload)
      return true unless @validate_block
      @validate_block.call(key, value, payload)
    end

    def message(key, value, payload)
      return nil unless @message_block
      @message_block.call(key, value, payload)
    end
  end
end
