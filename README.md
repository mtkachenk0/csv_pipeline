# csv_pipeline

A Ruby library for processing CSV records through a configurable pipeline of composable policies.

Each field declaration owns an ordered list of policies. Policies are defined once and reused across pipelines. The pipeline collects all errors — nothing stops on the first failure.

## Setup

```bash
bundle install
bundle exec rspec      # run the test suite
ruby examples/demo.rb  # run the demo against examples/sample.csv
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
|---|---|---|
| `present` | validate | fails when value is blank |
| `format(regexp)` | validate | fails when value does not match regexp |
| `default(value)` | transform | sets value when blank; skipped otherwise |
| `normalize_email` | transform | downcases and strips whitespace |

## Custom Policies

No library changes needed. Call `Pipeline.define_policy` before building your pipeline:

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

Each policy defines up to four optional blocks. All blocks receive `(key, value, payload)` where `payload` is the full record hash — enabling cross-field logic.

| Block | Returns | Purpose |
|---|---|---|
| `eligible` | Boolean | Guard — skip policy entirely if false. Defaults to always run. |
| `transform` | New value | Mutates the field. Runs before `validate` on the same policy. |
| `validate` | Boolean | `true` = valid, `false` = invalid. Defaults to always valid. |
| `message` | String | Error message when `validate` returns false. |

```ruby
# Cross-field example: email required only when name is present
Pipeline.define_policy(:required_when_named) do
  eligible { |_key, _value, payload| !payload[:name].to_s.strip.empty? }
  validate { |_key, value,  _payload| !value.to_s.strip.empty? }
  message  { |key,  _value, _payload| "#{key} is required when name is present" }
end

# Parameterised example
Pipeline.define_policy(:one_of) do |*allowed|
  validate { |_key, value, _payload| allowed.include?(value.to_s) }
  message  { |key,  _value, _payload| "#{key} must be one of: #{allowed.join(', ')}" }
end
```

### Execution order

For each field, policies run left to right:
1. `eligible?` checked — if false, skip this policy entirely
2. `transform` applied — record value updated in place
3. `validate` checked — if false, `message` appended to errors

All errors across all fields accumulate into `result.errors`.

## Result

```ruby
result.valid?   # => true / false
result.record   # => { name: "Alice", email: "alice@example.com", age: "30" }
result.errors   # => [{ field: :email, message: "email has invalid format" }]
```

## Design Decisions

**Field-centric API.** Grouping policies by field (`field(:email).normalize_email.present.format(...)`) reads naturally and avoids scattering field logic across the pipeline definition.

**Four-block policy descriptor.** Separating `eligible`, `transform`, `validate`, and `message` into explicit blocks makes intent clear and keeps each concern independently testable. A policy can be a pure transform, a pure validator, or both — no special cases.

**`payload` in every block.** All four blocks receive the full record. This unlocks cross-field logic (conditionals, comparisons) without a separate "cross-field validation" concept.

**Error aggregation.** The pipeline never stops early. Every field and every policy runs. `result.errors` is always the complete picture for that row.

**Duck-typed extensibility.** `apply(:name)` resolves any registered name. Custom policies are first-class — indistinguishable from built-ins at the call site. Adding a new policy requires zero changes to library code.

**No runtime dependencies.** Uses only Ruby stdlib (`csv`).
