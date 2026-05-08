# Policy Error Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rescue `StandardError` from any policy block, mark the field invalid with a structured error entry, and let pipelines opt in to stopping at the first error per field.

**Architecture:** `Field#process` wraps each policy's 4-step execution in a single `begin/rescue` block, appending `{ field:, message:, exception: }` on catch. `Pipeline#initialize` accepts `on_error: :continue | :stop`, validates it, and threads the value through `append_result` → `Field#process`.

**Tech Stack:** Ruby stdlib only. RSpec for tests.

---

## File Map

| File | Action | What changes |
|---|---|---|
| `lib/csv_pipeline/field.rb` | Modify | Add `on_error:` kwarg + rescue block to `#process` |
| `lib/csv_pipeline/pipeline.rb` | Modify | Accept + validate `on_error:` in `initialize`; pass to `Field#process` |
| `spec/csv_pipeline/field_spec.rb` | Modify | Add `describe "error handling"` block |
| `spec/csv_pipeline/pipeline_spec.rb` | Modify | Add `on_error:` option tests |
| `README.md` | Modify | Document `on_error:` option and exception error entry shape |

---

## Task 1: Failing tests — `Field#process` error handling

**Files:**
- Modify: `spec/csv_pipeline/field_spec.rb`

- [ ] **Step 1: Add error-handling policies to the `before` block in `field_spec.rb`**

Open `spec/csv_pipeline/field_spec.rb`. Inside the existing `before` block (after the last `define_policy` call, before `end`), add:

```ruby
CsvPipeline::Pipeline.define_policy(:raises_on_transform) do
  transform { |_k, _v, _p| raise ZeroDivisionError, "divided by 0" }
end
CsvPipeline::Pipeline.define_policy(:raises_on_eligible) do
  eligible { |_k, _v, _p| raise RuntimeError, "eligible blew up" }
end
CsvPipeline::Pipeline.define_policy(:raises_on_validate) do
  validate { |_k, _v, _p| raise ArgumentError, "validate blew up" }
end
CsvPipeline::Pipeline.define_policy(:raises_on_message) do
  validate { |_k, _v, _p| false }
  message  { |_k, _v, _p| raise TypeError, "message blew up" }
end
CsvPipeline::Pipeline.define_policy(:safe_policy) do
  validate { |_k, v, _p| v == "safe" }
  message  { |k, _v, _p| "#{k} not safe" }
end
```

- [ ] **Step 2: Add the `describe "error handling"` block to `field_spec.rb`**

Add this after the closing `end` of the existing `describe "#process"` block:

```ruby
describe "error handling" do
  it "catches raising transform — error has :exception key and message format" do
    record = { email: "test@example.com" }
    errors = field.apply(:raises_on_transform).process(record)
    expect(errors.length).to eq(1)
    expect(errors.first[:field]).to eq(:email)
    expect(errors.first[:message]).to eq("ZeroDivisionError: divided by 0")
    expect(errors.first[:exception]).to be_a(ZeroDivisionError)
  end

  it "catches raising eligible block" do
    record = { email: "test@example.com" }
    errors = field.apply(:raises_on_eligible).process(record)
    expect(errors.length).to eq(1)
    expect(errors.first[:exception]).to be_a(RuntimeError)
  end

  it "catches raising validate block" do
    record = { email: "test@example.com" }
    errors = field.apply(:raises_on_validate).process(record)
    expect(errors.length).to eq(1)
    expect(errors.first[:exception]).to be_a(ArgumentError)
  end

  it "catches raising message block" do
    record = { email: "test@example.com" }
    errors = field.apply(:raises_on_message).process(record)
    expect(errors.length).to eq(1)
    expect(errors.first[:exception]).to be_a(TypeError)
  end

  it "continues to next policy by default after error" do
    record = { email: "not_safe" }
    errors = field.apply(:raises_on_transform).apply(:safe_policy).process(record)
    expect(errors.length).to eq(2)
    expect(errors.first[:exception]).to be_a(ZeroDivisionError)
    expect(errors.last[:message]).to eq("email not safe")
  end

  it "stops at erroring policy when on_error: :stop" do
    record = { email: "not_safe" }
    errors = field.apply(:raises_on_transform).apply(:safe_policy).process(record, on_error: :stop)
    expect(errors.length).to eq(1)
    expect(errors.first[:exception]).to be_a(ZeroDivisionError)
  end
end
```

- [ ] **Step 3: Run the new tests — verify they all fail**

```bash
bundle exec rspec spec/csv_pipeline/field_spec.rb --format documentation 2>&1 | tail -20
```

Expected: 6 failures, errors like `expected: 1 got: 0` or `NoMethodError` or exceptions propagating.

---

## Task 2: Implement rescue in `Field#process`

**Files:**
- Modify: `lib/csv_pipeline/field.rb`

- [ ] **Step 1: Replace `#process` with the rescuing version**

Replace the entire `process` method (lines 22–34 of `lib/csv_pipeline/field.rb`):

```ruby
def process(record, on_error: :continue)
  errors = []
  @policies.each do |policy|
    begin
      value = record[@name]
      next unless policy.eligible?(@name, value, record)
      record[@name] = policy.transform(@name, value, record)
      value = record[@name]
      unless policy.valid?(@name, value, record)
        errors << { field: @name, message: policy.message(@name, value, record) }
      end
    rescue StandardError => e
      errors << { field: @name, message: "#{e.class}: #{e.message}", exception: e }
      break if on_error == :stop
    end
  end
  errors
end
```

- [ ] **Step 2: Run field specs — all must pass**

```bash
bundle exec rspec spec/csv_pipeline/field_spec.rb --format documentation
```

Expected: all examples pass, 0 failures.

- [ ] **Step 3: Run full suite — no regressions**

```bash
bundle exec rspec
```

Expected: all examples pass.

- [ ] **Step 4: Commit**

```bash
git add lib/csv_pipeline/field.rb spec/csv_pipeline/field_spec.rb
git commit -m "feat: rescue StandardError in Field#process, add on_error: :stop support"
```

---

## Task 3: Failing tests — `Pipeline` `on_error:` option

**Files:**
- Modify: `spec/csv_pipeline/pipeline_spec.rb`

- [ ] **Step 1: Read current pipeline_spec to find a good insertion point**

Open `spec/csv_pipeline/pipeline_spec.rb` and note where to append a new `describe` block.

- [ ] **Step 2: Add the `on_error:` describe block**

Append before the final `end` of the `RSpec.describe CsvPipeline::Pipeline` block:

```ruby
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
```

- [ ] **Step 3: Run new pipeline tests — verify they fail**

```bash
bundle exec rspec spec/csv_pipeline/pipeline_spec.rb --format documentation 2>&1 | tail -15
```

Expected: 3 failures — `ArgumentError` not raised, wrong error counts.

---

## Task 4: Implement `on_error:` in `Pipeline`

**Files:**
- Modify: `lib/csv_pipeline/pipeline.rb`

- [ ] **Step 1: Add constant and update `initialize`**

Add after the `class Pipeline` line (before `def self.define_policy`):

```ruby
VALID_ON_ERROR_VALUES = %i[continue stop].freeze
```

Replace the existing `initialize` method:

```ruby
def initialize(on_error: :continue, &block)
  raise ArgumentError, "on_error must be :continue or :stop, got #{on_error.inspect}" unless VALID_ON_ERROR_VALUES.include?(on_error)
  @fields     = []
  @header_map = nil
  @on_error   = on_error
  instance_eval(&block) if block
end
```

- [ ] **Step 2: Update `append_result` to thread `on_error:`**

Replace the existing `append_result` method:

```ruby
def append_result(record, results)
  all_errors = []
  @fields.each { |f| all_errors.concat(f.process(record, on_error: @on_error)) }
  results << Result.new(record: record, errors: all_errors)
end
```

- [ ] **Step 3: Run pipeline specs — all must pass**

```bash
bundle exec rspec spec/csv_pipeline/pipeline_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 4: Run full suite — no regressions**

```bash
bundle exec rspec
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/csv_pipeline/pipeline.rb spec/csv_pipeline/pipeline_spec.rb
git commit -m "feat: add on_error: option to Pipeline, validate at init time"
```

---

## Task 5: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Error Handling section after Quick Start**

After the closing ` ``` ` of the Quick Start code block (after line 35), insert:

```markdown
## Error Handling

By default the pipeline continues to remaining policies when a block raises. To stop field processing at the first exception, pass `on_error: :stop`:

```ruby
pipeline = Pipeline.new(on_error: :stop) do
  field(:email).normalize_email.present.format(EMAIL)
  field(:name).present
end
```

When a policy block raises, the error entry gains an `:exception` key alongside the standard `:field` and `:message`:

```ruby
result.errors
# validation failure (normal):
# => [{ field: :email, message: "email has invalid format" }]

# policy block raised:
# => [{ field: :email, message: "ZeroDivisionError: divided by 0", exception: #<ZeroDivisionError: divided by 0> }]
```

Valid values for `on_error:` are `:continue` (default) and `:stop`. Any other value raises `ArgumentError` at pipeline construction time.
```

- [ ] **Step 2: Update the "Error aggregation" Design Decision**

Find this line in the Design Decisions section:

```
**Error aggregation.** The pipeline never stops early. Every field and every policy runs. `result.errors` is always the complete picture for that row.
```

Replace with:

```
**Error aggregation.** By default every field and every policy runs — `result.errors` is always the complete picture for that row. Pass `on_error: :stop` to `Pipeline.new` to halt a field's policy chain at the first exception; other fields still process fully. If a policy block raises, the error entry includes an `:exception` key with the original exception object.
```

- [ ] **Step 3: Verify README renders correctly**

```bash
cat README.md | grep -A 5 "Error Handling"
cat README.md | grep -A 3 "Error aggregation"
```

Expected: both sections show updated content.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document on_error: option and exception error entry shape"
```
