# AGENTS.md — odin-jsonutil

Rules and policy for coding agents on the odin-jsonutil codebase — not
session records or measurements. User-facing documentation lives in
README.md and docs/.

# Project description

## Overview

odin-jsonutil is the JSON value layer for Odin (pure Odin, `core:*`
only, no foreign imports): casting and member access over
`core:encoding/json` values, the construction helpers that replace map
literals, the wire serializer (`marshal_value_unsorted` — object keys
appear in the map's iteration order), the deep-clone/release pair
(`clone_value`/`free_value`) that moves a value across a lifetime
boundary, and `json_quote`, which renders any string — invalid UTF-8
included — as a valid JSON string literal. The package knows nothing
about its consumers; odin-jsonrpc builds its wire faces on these
helpers.

### Package layout and dependency direction

```
src/jsonutil/   the value layer (the whole library)
tests/          the component suite, importing it through the
                `jsonutil:` collection
```

- Consumers mount this tree as the `jsonutil:` collection
  (`-collection:jsonutil=<path-to-src>`); the collection name is the
  library's stable identity and must not collide with a host's own
  collection names.
- No process-global variables, no threads, no clocks: state is the
  value and the allocator the caller pins at construction.

# Project principles

- **Correctness, processing performance, and resource behaviour are the
  product.** Allocation counts are this library's cost: every clone
  allocates exactly what its release frees, and the wire paths take no
  copy they do not need.
- **`core:encoding/json`'s `Value` is the value model.** The helpers
  add ownership discipline and wire form; they never build a second
  representation.
- **Every allocation has one owner and an explicit home allocator.**
  Values never borrow across a lifetime boundary: what must outlive
  its source is deep-cloned, map key bytes included.
- **Verdicts come from artifacts.** Suite outcomes are read from the
  suite log, never from the exit status alone.
- **Write for the next reader.** Comments state constraints the code
  cannot show; no text cites material the reader does not have.
  Enforced in: Comment self-containment.

## Comment self-containment

Committed code, docs, and error strings must be self-contained: no
citations of private notebooks, design-record numbers, or local
machine paths — every such citation dangles for readers without the
referenced material. State the constraint in prose where it matters.

Exact numbers that move while the code evolves (suite sizes, default
values, timings) rot between edits; where a magnitude carries a rule,
name the identifier that owns the exact value.

# Development guide

## Build, test, and measure

```sh
just check        # odin check -vet -strict-style -no-entry-point, the package
just test         # odin test tests (ODIN_TEST_THREADS=1), log-gated
```

- The Odin compiler is pinned to `dev-2026-10-nightly:84bc3fc` (the
  frozen `dev-2026-10` release; CI asserts the hash). After a toolchain
  move, re-run every gate.
- `just test` writes `tmp/test.log`: the runner's exit status is
  honored first (a compile failure is never a green run), then the
  log gate fails on any match of
  `\[ERROR\]|\[FATAL\]|\[WARN \]|\[WARN\]|\+\+\+ leak|bad free|out of range`.
  The `[WARN ]` alternative is load-bearing (the framework prints its
  per-test leak blocks under a padded header); always `grep -a` (a
  failing test can spill NUL bytes and make grep treat the log as
  binary). The leak discipline is zero leak lines — `free_value`'s
  correctness is verified by this gate.
- Do NOT use `-define:ODIN_TEST_NAMES` single-test builds — they change
  the binary's layout; the filter exists only as a `-define:` (an
  `ODIN_TEST_NAMES` environment variable does not filter at all).
- `tmp/` is recipe scratch — gitignored.
- Commits are conventional style (`feat:`, `fix:`, …); only when the
  user asks.

# Development rules in detail

## Design rules

- **Naming**: multiword types `Word_Word`; procs snake_case; allocator
  fields `allocator` (short `a` for procedure parameters).
- **Map literals are disabled**: objects are created empty with an
  explicit allocator (`json_object`) and filled through
  `obj_set`/`obj_set_object` on a `^map`. A map value copied out of a
  `json.Value` carries its own header — writes through the copy leave
  the stored map's count stale and its lookups miss — so the value
  union is entered only after the last write.
- **Values never borrow across a lifetime boundary**: what must outlive
  the source arena is deep-cloned (`clone_value`), map key bytes
  included — Odin maps store key headers, so key bytes are the
  inserter's ownership. `free_value` is the release counterpart, and it
  may only be applied to a value whose allocations all came from one
  allocator — exactly what `clone_value` produces.
- **Scalars and null carry no allocation**: `clone_value` passes them
  through, `free_value` ignores them; `clone_value(nil)` is nil.
- **The wire serializer does not sort keys** (`marshal_value_unsorted`):
  JSON objects are unordered on the wire; deterministic bytes are the
  caller's job. `json_quote` escapes C0 controls as `\u00xx` with
  lowercase hex and re-encodes invalid UTF-8 as U+FFFD — its output is
  always a valid JSON string literal whatever came in.

## Testing conventions

- The suite is synchronous — no threads, no clocks, no settle waits.
- Every `make` in a test has its matching release (arena destroy or
  `free_value`/`delete`); the zero-leak log gate is the assertion.

## Cross-platform

- The `sh`-scripted `test` recipe needs Git Bash's `sh` on PATH on
  Windows; the CI runner image carries it.

# Reference

## Odin language and stdlib

- `mem.Allocator` is the two-field `{procedure, data}` struct.
- A map carries its creating allocator through growth (the growth
  allocation is `.Alloc_Non_Zeroed` on that allocator), and an insert
  whose growth allocation fails is silently dropped — `len` unmoved,
  no error.
- `json.Object` is `map[string]json.Value`; `json.Array` is
  `[dynamic]json.Value`. `json.parse_string` parses numbers as Floats
  unless `parse_integers` is set — round-trip tests that expect
  `json.Integer` must set it.
- String-literal escapes are `\x` + two hex digits and `\u` + four
  (no `\u{...}` braced form on the pinned toolchain).

## Specification

- JSON text follows RFC 8259; the value model is `core:encoding/json`'s
  `Value`, and `json.unparse`'s escape behavior on the pinned toolchain
  is part of the wire output — re-check it whenever the pin moves.
