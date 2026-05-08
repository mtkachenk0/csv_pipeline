# CSV Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Ruby gem that processes CSV records through a configurable field-centric pipeline of composable policies.

**Architecture:** Each `Field` holds an ordered list of `Policy` objects applied in sequence. Policies are defined via a builder DSL with four optional blocks (`transform`, `validate`, `eligible`, `message`) — all receiving `(key, value, payload)`. `Pipeline` provides a class-level `define_policy` DSL and processes CSV files, returning one `Result` per row with aggregated errors.

**Tech Stack:** Ruby 3.x, stdlib CSV, RSpec 3.x (no runtime dependencies)

---

## File Map

| File | Role |
|------|------|
| `lib/csv_pipeline/version.rb` | VERSION constant |
| `lib/csv_pipeline/policy.rb` | Value object: 4 optional blocks |
| `lib/csv_pipeline/policy_builder.rb` | DSL context, collects blocks, builds Policy |
| `lib/csv_pipeline/policy_definition.rb` | Factory wrapper, instantiates Policy with args |
| `lib/csv_pipeline/policy_registry.rb` | name → PolicyDefinition store + `reset!` |
| `lib/csv_pipeline/field.rb` | Fluent builder: chains policies, runs them per record |
| `lib/csv_pipeline/result.rb` | Immutable value object: record + errors + valid? |
| `lib/csv_pipeline/pipeline.rb` | DSL entry point + CSV processing |
| `lib/csv_pipeline/built_in_policies.rb` | Registers present, format, default, normalize_email |
| `lib/csv_pipeline.rb` | Require all + `Pipeline = CsvPipeline::Pipeline` alias |
| `spec/spec_helper.rb` | RSpec config + reset/re-register built-ins per test |
| `spec/csv_pipeline/policy_spec.rb` | Unit: Policy |
| `spec/csv_pipeline/policy_builder_spec.rb` | Unit: PolicyBuilder |
| `spec/csv_pipeline/policy_registry_spec.rb` | Unit: PolicyRegistry |
| `spec/csv_pipeline/field_spec.rb` | Unit: Field |
| `spec/csv_pipeline/result_spec.rb` | Unit: Result |
| `spec/csv_pipeline/pipeline_spec.rb` | Unit: Pipeline DSL |
| `spec/csv_pipeline/integration_spec.rb` | End-to-end with sample.csv |
| `examples/sample.csv` | Valid + invalid records |
| `examples/demo.rb` | Runnable demo |
| `csv_pipeline.gemspec` | Gem spec |
| `Gemfile` | Source + gemspec |
| `README.md` | Setup + design decisions |

---

## Task 1: Project Skeleton

**Files:**
- Create: `csv_pipeline.gemspec`
- Create: `Gemfile`
- Create: `lib/csv_pipeline/version.rb`
- Create: `lib/csv_pipeline.rb`
- Create: `spec/spec_helper.rb`

- [ ] **Step 1: Create gemspec**

```ruby
# csv_pipeline.gemspec
# frozen_string_literal: true

require_relative "lib/csv_pipeline/version"

Gem::Specification.new do |spec|
  spec.name          = "csv_pipeline"
  spec.version       = CsvPipeline::VERSION
  spec.authors       = ["Maxim Tkachenko"]
  spec.summary       = "Configurable CSV processing pipeline with composable policies"
  spec.files         = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
```

- [ ] **Step 2: Create Gemfile**

```ruby
# Gemfile
# frozen_string_literal: true

source "https://rubygems.org"

gemspec
```

- [ ] **Step 3: Create version file**

```ruby
# lib/csv_pipeline/version.rb
# frozen_string_literal: true

module CsvPipeline
  VERSION = "0.1.0"
end
```

- [ ] **Step 4: Create entry point (stub — will fill as classes are added)**

```ruby
# lib/csv_pipeline.rb
# frozen_string_literal: true

require "csv"
require_relative "csv_pipeline/version"
```

- [ ] **Step 5: Create spec_helper stub**

```ruby
# spec/spec_helper.rb
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "csv_pipeline"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
end
```

- [ ] **Step 6: Install gems**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle install
```

Expected: `Bundle complete!` with rspec installed.

- [ ] **Step 7: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git init && git add . && git commit -m "chore: project skeleton"
```

---

## Task 2: Policy Class

**Files:**
- Create: `lib/csv_pipeline/policy.rb`
- Create: `spec/csv_pipeline/policy_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/csv_pipeline/policy_spec.rb
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/policy_spec.rb
```

Expected: fails with `uninitialized constant CsvPipeline::Policy`

- [ ] **Step 3: Implement Policy**

```ruby
# lib/csv_pipeline/policy.rb
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
```

- [ ] **Step 4: Add require to entry point**

Append to `lib/csv_pipeline.rb`:
```ruby
require_relative "csv_pipeline/policy"
```

- [ ] **Step 5: Run tests — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/policy_spec.rb
```

Expected: 7 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: add Policy value object"
```

---

## Task 3: PolicyBuilder Class

**Files:**
- Create: `lib/csv_pipeline/policy_builder.rb`
- Create: `spec/csv_pipeline/policy_builder_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/csv_pipeline/policy_builder_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe CsvPipeline::PolicyBuilder do
  subject(:builder) { described_class.new }

  describe "#build" do
    it "builds a Policy with no-op defaults when no blocks set" do
      policy = builder.build
      expect(policy).to be_a(CsvPipeline::Policy)
      expect(policy.eligible?(:k, "v", {})).to be true
      expect(policy.transform(:k, "v", {})).to eq("v")
      expect(policy.valid?(:k, "v",   {})).to be true
      expect(policy.message(:k, "v",  {})).to be_nil
    end

    it "captures and uses transform block" do
      builder.transform { |_k, v, _p| v.upcase }
      expect(builder.build.transform(:k, "hi", {})).to eq("HI")
    end

    it "captures and uses validate block" do
      builder.validate { |_k, v, _p| v != "" }
      expect(builder.build.valid?(:k, "",  {})).to be false
      expect(builder.build.valid?(:k, "x", {})).to be true
    end

    it "captures and uses eligible block" do
      builder.eligible { |_k, v, _p| v.nil? }
      expect(builder.build.eligible?(:k, nil, {})).to be true
      expect(builder.build.eligible?(:k, "x", {})).to be false
    end

    it "captures and uses message block" do
      builder.message { |k, _v, _p| "#{k} is required" }
      expect(builder.build.message(:name, "", {})).to eq("name is required")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/policy_builder_spec.rb
```

Expected: fails with `uninitialized constant CsvPipeline::PolicyBuilder`

- [ ] **Step 3: Implement PolicyBuilder**

```ruby
# lib/csv_pipeline/policy_builder.rb
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
```

- [ ] **Step 4: Add require to entry point**

Append to `lib/csv_pipeline.rb`:
```ruby
require_relative "csv_pipeline/policy_builder"
```

- [ ] **Step 5: Run tests — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/policy_builder_spec.rb
```

Expected: 5 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: add PolicyBuilder DSL context"
```

---

## Task 4: PolicyDefinition + PolicyRegistry

**Files:**
- Create: `lib/csv_pipeline/policy_definition.rb`
- Create: `lib/csv_pipeline/policy_registry.rb`
- Create: `spec/csv_pipeline/policy_registry_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/csv_pipeline/policy_registry_spec.rb
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
  end

  describe ".reset!" do
    it "clears all registered policies" do
      described_class.define(:temp) { transform { |_k, v, _p| v } }
      described_class.reset!
      expect { described_class.fetch(:temp) }.to raise_error(KeyError)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/policy_registry_spec.rb
```

Expected: fails with `uninitialized constant CsvPipeline::PolicyRegistry`

- [ ] **Step 3: Implement PolicyDefinition**

```ruby
# lib/csv_pipeline/policy_definition.rb
# frozen_string_literal: true

module CsvPipeline
  class PolicyDefinition
    def initialize(&factory)
      @factory = factory
    end

    def instantiate(*args)
      builder = PolicyBuilder.new
      builder.instance_exec(*args, &@factory)
      builder.build
    end
  end
end
```

- [ ] **Step 4: Implement PolicyRegistry**

```ruby
# lib/csv_pipeline/policy_registry.rb
# frozen_string_literal: true

module CsvPipeline
  module PolicyRegistry
    @policies = {}

    def self.define(name, &factory)
      @policies[name.to_sym] = PolicyDefinition.new(&factory)
    end

    def self.fetch(name, *args)
      key = name.to_sym
      raise KeyError, "Unknown policy: #{key.inspect}" unless @policies.key?(key)
      @policies[key].instantiate(*args)
    end

    def self.reset!
      @policies = {}
    end
  end
end
```

- [ ] **Step 5: Add requires to entry point**

Append to `lib/csv_pipeline.rb`:
```ruby
require_relative "csv_pipeline/policy_definition"
require_relative "csv_pipeline/policy_registry"
```

- [ ] **Step 6: Run tests — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/policy_registry_spec.rb
```

Expected: 4 examples, 0 failures

- [ ] **Step 7: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: add PolicyDefinition and PolicyRegistry"
```

---

## Task 5: Field Class

**Files:**
- Create: `lib/csv_pipeline/field.rb`
- Create: `spec/csv_pipeline/field_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/csv_pipeline/field_spec.rb
# frozen_string_literal: true

require "spec_helper"

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
  end

  subject(:field) { described_class.new(:email) }

  describe "#apply" do
    it "returns self for chaining" do
      expect(field.apply(:upcase_t)).to be(field)
    end

    it "appends one policy per call" do
      field.apply(:upcase_t).apply(:no_digits)
      expect(field.policies.length).to eq(2)
    end

    it "raises KeyError for unknown policy name" do
      expect { field.apply(:nonexistent) }.to raise_error(KeyError)
    end
  end

  describe "#process" do
    it "mutates record field value via transform" do
      record = { email: "hello" }
      field.apply(:upcase_t).process(record)
      expect(record[:email]).to eq("HELLO")
    end

    it "collects validation errors without stopping" do
      record = { email: "abc123" }
      errors = field.apply(:no_digits).process(record)
      expect(errors).to eq([{ field: :email, message: "email must not contain digits" }])
    end

    it "collects multiple errors across policies on same field" do
      record = { email: "a1" }
      # no_digits AND skip_blank (value "a1" is non-blank but length <= 2)
      errors = field.apply(:no_digits).apply(:skip_blank).process(record)
      expect(errors.length).to eq(2)
    end

    it "skips policy entirely when eligible? returns false" do
      record = { email: "" }
      errors = field.apply(:skip_blank).process(record)
      expect(errors).to be_empty
    end

    it "runs transform before validate on the same field" do
      record = { email: "hello" }
      # upcase first → "HELLO", then check_lower fails
      errors = field.apply(:upcase_t).apply(:check_lower).process(record)
      expect(errors).to eq([{ field: :email, message: "email must be lowercase" }])
    end

    it "passes the full record as payload" do
      CsvPipeline::Pipeline.define_policy(:uses_payload) do
        transform { |_k, _v, payload| payload[:other].to_s.reverse }
      end
      record = { email: "ignored", other: "abc" }
      described_class.new(:email).apply(:uses_payload).process(record)
      expect(record[:email]).to eq("cba")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/field_spec.rb
```

Expected: fails — Pipeline and Field not defined yet.

- [ ] **Step 3: Implement Field**

```ruby
# lib/csv_pipeline/field.rb
# frozen_string_literal: true

module CsvPipeline
  class Field
    attr_reader :name, :policies

    def initialize(name)
      @name     = name.to_sym
      @policies = []
    end

    def apply(policy_name, *args)
      @policies << PolicyRegistry.fetch(policy_name, *args)
      self
    end

    def present         = apply(:present)
    def normalize_email = apply(:normalize_email)
    def format(regexp)  = apply(:format, regexp)
    def default(value)  = apply(:default, value)

    def process(record)
      errors = []
      @policies.each do |policy|
        value = record[@name]
        next unless policy.eligible?(@name, value, record)
        record[@name] = policy.transform(@name, value, record)
        value = record[@name]
        unless policy.valid?(@name, value, record)
          errors << { field: @name, message: policy.message(@name, value, record) }
        end
      end
      errors
    end
  end
end
```

- [ ] **Step 4: Add stub Pipeline class and require to entry point**

We need `CsvPipeline::Pipeline.define_policy` for the before block in field_spec. Add a stub pipeline:

```ruby
# lib/csv_pipeline/pipeline.rb (stub — will be filled in Task 7)
# frozen_string_literal: true

module CsvPipeline
  class Pipeline
    def self.define_policy(name, &factory)
      PolicyRegistry.define(name, &factory)
    end
  end
end
```

Append to `lib/csv_pipeline.rb`:
```ruby
require_relative "csv_pipeline/field"
require_relative "csv_pipeline/pipeline"
```

- [ ] **Step 5: Run tests — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/field_spec.rb
```

Expected: 8 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: add Field with fluent policy chaining"
```

---

## Task 6: Result Class

**Files:**
- Create: `lib/csv_pipeline/result.rb`
- Create: `spec/csv_pipeline/result_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/csv_pipeline/result_spec.rb
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/result_spec.rb
```

Expected: fails with `uninitialized constant CsvPipeline::Result`

- [ ] **Step 3: Implement Result**

```ruby
# lib/csv_pipeline/result.rb
# frozen_string_literal: true

module CsvPipeline
  class Result
    attr_reader :record, :errors

    def initialize(record:, errors:)
      @record = record
      @errors = errors.freeze
    end

    def valid?
      @errors.empty?
    end
  end
end
```

- [ ] **Step 4: Add require to entry point**

Append to `lib/csv_pipeline.rb` (before the pipeline require):
```ruby
require_relative "csv_pipeline/result"
```

- [ ] **Step 5: Run tests — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/result_spec.rb
```

Expected: 4 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: add Result value object"
```

---

## Task 7: Pipeline Class (full implementation)

**Files:**
- Modify: `lib/csv_pipeline/pipeline.rb` (replace stub)
- Create: `spec/csv_pipeline/pipeline_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/csv_pipeline/pipeline_spec.rb
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

    it "returns a Field instance" do
      pipeline = described_class.new { field(:name) }
      expect(pipeline).to respond_to(:process)
    end

    it "allows chaining policies on the returned field" do
      expect {
        described_class.new { field(:name).apply(:noop) }
      }.not_to raise_error
    end
  end

  describe "#process" do
    let(:csv_path) { File.expand_path("../../../examples/sample.csv", __dir__) }

    before do
      described_class.define_policy(:present) do
        validate { |_k, v, _p| !v.to_s.strip.empty? }
        message  { |k, _v, _p| "#{k} can't be blank" }
      end
    end

    it "returns one Result per CSV data row" do
      pipeline = described_class.new { field(:name).present }
      results  = pipeline.process(csv_path)
      expect(results.length).to eq(5)
    end

    it "returns Result objects" do
      pipeline = described_class.new { field(:name) }
      results  = pipeline.process(csv_path)
      expect(results).to all(be_a(CsvPipeline::Result))
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
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/pipeline_spec.rb
```

Expected: most pass (stub has `define_policy`), `#process` tests fail — method not defined.

- [ ] **Step 3: Implement full Pipeline**

```ruby
# lib/csv_pipeline/pipeline.rb
# frozen_string_literal: true

require "csv"

module CsvPipeline
  class Pipeline
    def self.define_policy(name, &factory)
      PolicyRegistry.define(name, &factory)
    end

    def initialize(&block)
      @fields = []
      instance_eval(&block) if block
    end

    def field(name)
      f = Field.new(name)
      @fields << f
      f
    end

    def process(csv_path)
      results = []
      CSV.foreach(csv_path, headers: true, header_converters: :symbol) do |row|
        record     = row.to_h
        all_errors = []
        @fields.each { |f| all_errors.concat(f.process(record)) }
        results << Result.new(record: record, errors: all_errors)
      end
      results
    end
  end
end
```

- [ ] **Step 4: Create sample CSV (needed for pipeline tests)**

```
name,email,age
Alice,alice@example.com,30
Bob,BOB@EXAMPLE.COM,17
,invalid-email,
Charlie,charlie@example.com,
,  ,25
```

Save to `examples/sample.csv`.

- [ ] **Step 5: Run tests — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/pipeline_spec.rb
```

Expected: all examples pass

- [ ] **Step 6: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: implement Pipeline DSL and CSV processing"
```

---

## Task 8: Built-in Policies

**Files:**
- Create: `lib/csv_pipeline/built_in_policies.rb`
- Update: `lib/csv_pipeline.rb`
- Update: `spec/spec_helper.rb`

- [ ] **Step 1: Implement BuiltInPolicies module**

```ruby
# lib/csv_pipeline/built_in_policies.rb
# frozen_string_literal: true

module CsvPipeline
  module BuiltInPolicies
    def self.register!
      Pipeline.define_policy(:present) do
        validate { |_key, value, _payload| !value.to_s.strip.empty? }
        message  { |key, _value, _payload| "#{key} can't be blank" }
      end

      Pipeline.define_policy(:format) do |regexp|
        validate { |_key, value, _payload| value.to_s.match?(regexp) }
        message  { |key, _value, _payload| "#{key} has invalid format" }
      end

      Pipeline.define_policy(:default) do |fill|
        eligible  { |_key, value, _payload| value.to_s.strip.empty? }
        transform { |_key, _value, _payload| fill }
      end

      Pipeline.define_policy(:normalize_email) do
        transform { |_key, value, _payload| value.to_s.downcase.strip }
      end
    end
  end
end
```

- [ ] **Step 2: Register on load in entry point**

Replace content of `lib/csv_pipeline.rb`:
```ruby
# frozen_string_literal: true

require "csv"
require_relative "csv_pipeline/version"
require_relative "csv_pipeline/policy"
require_relative "csv_pipeline/policy_builder"
require_relative "csv_pipeline/policy_definition"
require_relative "csv_pipeline/policy_registry"
require_relative "csv_pipeline/field"
require_relative "csv_pipeline/result"
require_relative "csv_pipeline/pipeline"
require_relative "csv_pipeline/built_in_policies"

CsvPipeline::BuiltInPolicies.register!

Pipeline = CsvPipeline::Pipeline
```

- [ ] **Step 3: Update spec_helper to reset + re-register per test**

```ruby
# spec/spec_helper.rb
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "csv_pipeline"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.before(:each) do
    CsvPipeline::PolicyRegistry.reset!
    CsvPipeline::BuiltInPolicies.register!
  end
end
```

- [ ] **Step 4: Run full suite — expect green**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec
```

Expected: all examples pass (some may warn about re-registrations — acceptable)

- [ ] **Step 5: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "feat: add built-in policies (present, format, default, normalize_email)"
```

---

## Task 9: Integration Spec

**Files:**
- Create: `spec/csv_pipeline/integration_spec.rb`

- [ ] **Step 1: Write integration tests**

```ruby
# spec/csv_pipeline/integration_spec.rb
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

  context "row 2 — Bob, uppercase email, valid age" do
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

  context "row 5 — blank name, whitespace email" do
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

      # "Alice" (5) and "Charlie" (7) pass; "Bob" (3) fails
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
        message  { |k, _v, _p| "#{k} must end with .com for VIPs" }
      end

      p = Pipeline.new { field(:email).apply(:vip_email) }
      results = p.process(csv_path)

      # Bob age=17 → skipped (eligible false)
      bob = results.find { |r| r.record[:name] == "Bob" }
      expect(bob.valid?).to be true
    end
  end

  context "payload access inside policy blocks" do
    it "allows cross-field logic" do
      Pipeline.define_policy(:required_when_named) do
        eligible { |_k, _v, payload| !payload[:name].to_s.strip.empty? }
        validate { |_k, v, _p| !v.to_s.strip.empty? }
        message  { |k, _v, _p| "#{k} required when name is present" }
      end

      p = Pipeline.new { field(:email).apply(:required_when_named) }
      # Row 3: blank name → policy skipped → no error
      result_row3 = p.process(csv_path)[2]
      expect(result_row3.errors).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run integration spec**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec spec/csv_pipeline/integration_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 3: Run full suite**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec --format documentation
```

Expected: all green, 0 failures

- [ ] **Step 4: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "test: add integration spec covering sample.csv and extensibility"
```

---

## Task 10: Demo + README

**Files:**
- Create: `examples/demo.rb`
- Create: `README.md`

- [ ] **Step 1: Create demo script**

```ruby
# examples/demo.rb
# frozen_string_literal: true

require_relative "../lib/csv_pipeline"

EMAIL_REGEXP = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

# Custom policy — no library changes needed
Pipeline.define_policy(:min_length) do |min|
  validate { |_key, value, _payload| value.to_s.length >= min }
  message  { |key, _value, _payload| "#{key} must be at least #{min} characters" }
end

pipeline = Pipeline.new do
  field(:email).normalize_email.present.format(EMAIL_REGEXP)
  field(:name).present.apply(:min_length, 2)
  field(:age).default("unknown")
end

puts "Processing #{File.basename(__dir__)}/sample.csv\n\n"

pipeline.process(File.expand_path("sample.csv", __dir__)).each_with_index do |result, i|
  row = i + 2
  if result.valid?
    puts "Row #{row} OK    #{result.record}"
  else
    msgs = result.errors.map { |e| "#{e[:field]}: #{e[:message]}" }.join(" | ")
    puts "Row #{row} ERROR #{msgs}"
    puts "       record: #{result.record}"
  end
end
```

- [ ] **Step 2: Run demo to verify output**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && ruby examples/demo.rb
```

Expected output (approximate):
```
Processing sample.csv

Row 2 OK    {:name=>"Alice", :email=>"alice@example.com", :age=>"30"}
Row 3 OK    {:name=>"Bob", :email=>"bob@example.com", :age=>"17"}
Row 4 ERROR name: can't be blank | email: email has invalid format
       record: {:name=>"", :email=>"invalid-email", :age=>"unknown"}
Row 5 OK    {:name=>"Charlie", :email=>"charlie@example.com", :age=>"unknown"}
Row 6 ERROR name: can't be blank | email: can't be blank | email: email has invalid format
       record: {:name=>"", :email=>"", :age=>"25"}
```

- [ ] **Step 3: Create README.md**

```markdown
# csv_pipeline

A Ruby library for processing CSV records through a configurable pipeline of composable policies.

## Setup

```bash
bundle install
bundle exec rspec      # run tests
ruby examples/demo.rb  # run demo
```

## Quick Start

```ruby
require "csv_pipeline"

EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

pipeline = Pipeline.new do
  field(:email).normalize_email.present.format(EMAIL)
  field(:name).present
  field(:age).default("unknown")
end

pipeline.process("data.csv").each do |result|
  if result.valid?
    puts "OK: #{result.record}"
  else
    result.errors.each { |e| puts "#{e[:field]}: #{e[:message]}" }
  end
end
```

## Built-in Policies

| Policy | Type | Description |
|--------|------|-------------|
| `present` | validate | fails if value is blank |
| `format(regexp)` | validate | fails if value doesn't match regexp |
| `default(value)` | transform | sets value when blank (skipped otherwise) |
| `normalize_email` | transform | downcases and strips whitespace |

## Defining Custom Policies

No library changes needed. Call `Pipeline.define_policy` anywhere before building a pipeline:

```ruby
Pipeline.define_policy(:min_length) do |min|
  validate { |_key, value, _payload| value.to_s.length >= min }
  message  { |key, _value, _payload| "#{key} must be at least #{min} characters" }
end

Pipeline.new do
  field(:name).present.apply(:min_length, 2)
end
```

### Policy DSL

Each policy may define four optional blocks. All receive `(key, value, payload)`:

| Block | Purpose |
|-------|---------|
| `eligible` | Guard — skip policy entirely if returns false. Default: always run. |
| `transform` | Mutate the field value. Return new value. Default: no-op. |
| `validate` | Return `true` (valid) or `false` (invalid). Default: always valid. |
| `message` | Return error string when validation fails. |

```ruby
Pipeline.define_policy(:required_for_adults) do
  eligible  { |_key, _value, payload| payload[:age].to_i >= 18 }
  validate  { |_key, value, _payload| !value.to_s.strip.empty? }
  message   { |key, _value, _payload| "#{key} is required for adults" }
end
```

`payload` is the full record hash — use it for cross-field logic.

## Design Decisions

**Field-centric API.** Rules belong to fields, not the other way around. `field(:email).present.format(...)` reads naturally and groups related checks.

**Four-block policy descriptor.** Separating `eligible`, `transform`, `validate`, and `message` makes each concern explicit and testable in isolation. A policy can be a pure transform, a pure validator, or both — without special-casing.

**Error aggregation.** The pipeline collects all errors across all fields and all policies. Nothing stops on first failure. Each `Result` carries the complete error list for that row.

**Duck-typed extensibility.** `apply(:name)` looks up any name in the registry. Custom policies are indistinguishable from built-ins at call site.

**No runtime dependencies.** Uses only Ruby stdlib (`csv`).
```

- [ ] **Step 4: Final test run**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && bundle exec rspec --format progress
```

Expected: all green, 0 failures

- [ ] **Step 5: Commit**

```bash
cd /Users/maximtkachenko/work/csv_pipeline && git add . && git commit -m "docs: add README and demo script"
```

---

## Verification

```bash
bundle exec rspec --format documentation   # all specs green
ruby examples/demo.rb                      # prints row-by-row results
```
