# Policy Error Handling — Design Spec

**Date:** 2026-05-08  
**Branch:** handle-edgecases  
**Status:** Approved

## Problem

Policy blocks (`eligible`, `transform`, `validate`, `message`) are developer-defined and may raise `StandardError`. Currently no rescue exists in `Field#process` — any exception crashes the entire pipeline run.

## Goal

- Catch exceptions from any of the four policy blocks
- Mark the affected field as invalid with a structured error entry
- Default: continue processing remaining policies after an error
- Optional: stop processing remaining policies for that field on first error (pipeline-level config)

## Scope

Three files change; no new files:

| File | Change |
|---|---|
| `lib/csv_pipeline/field.rb` | Add `on_error:` kwarg to `#process`; rescue per policy |
| `lib/csv_pipeline/pipeline.rb` | Accept `on_error:` in `initialize`; validate it; thread to `Field#process` |
| `README.md` | Document `on_error:` option and updated error entry shape |

`Result`, `Policy`, `PolicyBuilder`, `PolicyRegistry` — untouched.

## Error Entry Shape

Normal validation error (unchanged):
```ruby
{ field: :email, message: "email is invalid" }
```

Policy exception error (new `:exception` key):
```ruby
{ field: :email, message: "ZeroDivisionError: divided by 0", exception: <ZeroDivisionError> }
```

## `Field#process` Changes

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

Rescue scope: **all 4 steps of one policy as a unit**. If any step raises, the whole policy is failed — no partial execution within a policy iteration.

## `Pipeline` Changes

```ruby
VALID_ON_ERROR_VALUES = %i[continue stop].freeze

def initialize(on_error: :continue, &block)
  raise ArgumentError, "on_error must be :continue or :stop" unless VALID_ON_ERROR_VALUES.include?(on_error)
  @fields     = []
  @header_map = nil
  @on_error   = on_error
  instance_eval(&block) if block
end
```

`append_result` passes it through:
```ruby
def append_result(record, results)
  all_errors = []
  @fields.each { |f| all_errors.concat(f.process(record, on_error: @on_error)) }
  results << Result.new(record: record, errors: all_errors)
end
```

## Tests

### `field_spec.rb` (unit)

- Raising `transform` block → error entry present, has `:exception` key with correct exception object
- Raising `eligible` block → caught, error entry present
- Raising `validate` block → caught, error entry present
- Raising `message` block → caught, error entry present
- Default `on_error: :continue` → policy after raising policy still runs
- `on_error: :stop` → policy after raising policy is skipped

### `pipeline_spec.rb` (integration)

- `Pipeline.new(on_error: :stop)` → field stops at first erroring policy
- `Pipeline.new(on_error: :invalid_value)` → raises `ArgumentError`

## README Updates

1. `Pipeline.new` constructor — add `on_error:` option with values and default
2. Result section — update `result.errors` example to show `:exception` key for raised errors
3. Design Decisions — update "Error aggregation" note: default is continue, `:stop` available
