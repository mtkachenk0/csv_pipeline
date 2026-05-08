# frozen_string_literal: true

module CsvPipeline
  class PolicyBuilder
    def initialize
      @transform_block = nil
      @validate_block  = nil
      @eligible_block  = nil
      @message_block   = nil
    end

    def transform(&block) = @transform_block = block
    def validate(&block)  = @validate_block  = block
    def eligible(&block)  = @eligible_block  = block
    def message(&block)   = @message_block   = block

    def build
      Policy.new(
        transform: @transform_block,
        validate:  @validate_block,
        eligible:  @eligible_block,
        message:   @message_block
      )
    end
  end
end
