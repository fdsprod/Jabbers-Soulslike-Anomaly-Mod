---
name: tdd
display_name: "Test-Driven Development (TDD)"
description: "Drive implementation through failing tests. Red → Green → Refactor."
---

# Test-Driven Development (TDD)

## What this skill does

Test-Driven Development is an implementation discipline where tests are written before
the code they verify. Each unit of new behavior is specified as a failing test first.
The implementation is then written to satisfy that test — nothing more. The cycle repeats
for each unit of behavior.

**Red → Green → Refactor:**
1. **Red** — Write a failing test that defines the expected behavior
2. **Green** — Write the minimal implementation to make the test pass
3. **Refactor** — Clean up the implementation without changing behavior; tests remain green

The test is not documentation of code that already exists. It is a specification of
behavior that does not yet exist. This distinction is the discipline.

## Who writes the tests — separate, untainted authorship

The tests for a unit of work are authored by a **different agent than the one that implements
it** — the `test-author` agent. This is mandatory whenever this skill is active. When the same
agent writes both, the tests drift toward confirming the implementation it just built (and the
shortcuts it took) instead of independently specifying required behavior — the exact
anti-pattern above. A separate author that never sees the implementation cannot rubber-stamp
it. This mirrors the pipeline's existing untainted-payload pattern (Step 2 research, the
drift guard): the test-author receives the slice's **specification**, never the implementer's
code or reasoning.

## Contract → Red → Green (making test-first possible in any language)

Pure test-first can stall in statically-typed languages: a test cannot compile against a
foundational type that does not exist yet, producing a *compile*-red instead of a *behavioral*
red. The resolution is to let the test phase bootstrap the contract:

1. **Contract + Red** — the `test-author` writes **just-enough contract stubs** (the public
   signatures/types this slice introduces, each throwing the not-implemented equivalent) so the
   tests compile, then writes the failing tests. The stubs are structural scaffolding only — no
   logic — so they are not "the code under test." The result is a true behavioral red: tests
   compile and fail on assertions.
2. **Green** — the implementer fills the logic to satisfy the tests, and **never edits the
   tests**.
3. **Refactor** — clean up against the green suite, as below.

### Per-slice decision tree — pure test-first when able, degrade when not

```
For each unit of work where this skill is active:
  1. Structural/wiring only, no logic?  → this skill does not apply (see "When to apply"). No test-author.
  2. Can the contract be declared before the logic?
     • Yes → Contract+Red (test-author) → Green (implementer).   [pure TDD — the default]
     • No  → the contract is itself the unknown (a spike). Degrade to BLIND TEST-AFTER:
             the implementer builds the slice, then the SAME separate test-author writes tests
             from the spec only (reading the public surface to compile, never the implementation
             logic to derive assertions). Record the slice as test-after so the degradation is visible.
```

The separate, untainted authorship never degrades — only the test-first *ordering* does, and
only when the contract genuinely cannot precede the code.

## When to apply this skill

Apply when:
- New business logic, rules, or algorithms are being introduced
- Data transformation, computation, or validation behavior is being defined
- The expected inputs and outputs of new code can be stated before writing it
- Correctness must be verifiable and regress-proof over time

Do not apply when:
- The work is purely structural: wiring, configuration, or scaffolding with no logic
- Behavior is genuinely unknown until after an exploratory implementation (spike)
- A black-box dependency must be understood before tests can be meaningful — use
  Learning Tests first, then return to TDD for the code built around it

## What this skill requires

- Tests are authored by the separate `test-author` agent, not the implementer (see above)
- Tests are written and committed before the implementation they verify
- The test must fail before any implementation is written — a test that passes immediately
  is not verifying new behavior
- Test commits and implementation commits are kept separate
- The full suite stays green at every commit; regressions are resolved immediately
- Refactoring happens only against a green suite, never while tests are failing

## Language and framework agnosticism

This skill imposes no requirement on language, framework, or toolchain. Detect the
project's existing test framework from its configuration files, existing test files, build
manifests, and conventions. Use whatever is already in place. If no test framework exists,
surface that as a blocking question before proceeding — do not assume one.

## Relationship with Learning Tests

If Learning Tests are also active, they run first. Learning tests establish what external
or black-box code actually does; that knowledge informs what the TDD tests should assert
about the code being built around it.
