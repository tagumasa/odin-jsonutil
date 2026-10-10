# odin-jsonutil design

The specification the implementation governs against: the value model,
the construction and marshaling rules, and the clone/release ownership
pair. The code is the arbiter — where this document and the code
disagree, one of them is defective.

## The value model

`core:encoding/json`'s `Value` is the only representation:
`json.Object` is `map[string]json.Value`, `json.Array` is
`[dynamic]json.Value`, and the scalars are `String`/`Integer`/`Float`/
`Boolean` plus `Null`. The helpers in this package add ownership
discipline and wire form over that union — never a second
representation.

Odin maps store key headers, not key bytes: the key string an inserter
hands to the map remains the inserter's ownership. Every rule below
about cloning or freeing values therefore treats map keys as allocated
data.

## Construction

Map literals are disabled in this codebase, and the reason is a
representation hazard, not taste: a map value copied out of a
`json.Value` carries its own header, so writes through the copy leave
the stored map's count stale and its lookups miss. Objects are
therefore created empty with an explicit allocator (`json_object`) and
filled through `obj_set`/`obj_set_object`, which take a `^map`; the
value union is entered only after the last write (`obj_set_object`,
or `json.Value(json.Object(m))` for a root). Arrays come from
`json_array`, which copies the caller's items into a fresh dynamic
array in the given allocator.

`as_object`/`as_array` return shared views (the base map, the dynamic
array's slice), not copies — reads through them observe the value, and
writes go through the `^map` forms above. `obj_get` and `obj_get_bool`
are the member-access pair: absent keys and wrong-typed members read as
not-found and false.

## Marshaling

`marshal_value_unsorted` is the wire serializer: `json.unparse` with
the per-object key sort skipped, so object keys appear in the map's
iteration order. JSON objects are unordered on the wire, so the bytes
are legal for any consumer that parses them; a caller that needs
deterministic bytes for comparison or persistence sorts keys on its
own side. The suite checks multi-member objects by parse round-trip,
never by byte equality. Note the stdlib default when parsing back:
`json.parse_string` yields Floats for numbers unless `parse_integers`
is set.

`json_quote` renders one string as a JSON string literal: named
escapes for `"` `\` newline carriage return and tab, `\u00xx` with
lowercase hex for the remaining C0 controls, everything else
re-encoded as UTF-8. Its input contract is total: invalid UTF-8
decodes to U+FFFD under rune iteration and re-encodes, so the output
is always valid UTF-8 and always parses.

## The clone/release pair

`clone_value` deep-copies a value into an allocator: strings are
duplicated, arrays and maps rebuilt (keys cloned too), scalars pass
through, `nil` stays `nil`. `free_value` is the release counterpart:
strings, keys, array elements, and maps are freed recursively; scalars
and null are no-ops.

The pair exists for one rule: a value never borrows across a lifetime
boundary. A parsed value lives in its parse arena; the moment
something must outlive that arena, it is cloned into the destination
allocator, and the owner releases it with `free_value` rather than an
arena `free_all`. Both procs must agree on what the clone allocated —
the suite's zero-leak log gate is the verifier: a missed allocation
prints a leak block, a wrong pointer a bad free.

## Memory rules

- Every container is made with an explicit allocator on the library
  path (`json_object`, `json_array`, `clone_value` take one); defaults
  exist only as default parameters (`marshal_value_unsorted` defaults
  to the temp allocator, `clone_value` and `json_quote` to
  `context.allocator`).
- The home allocator is a property of the data: containers free
  through the allocator they stored at `make` (`free_value` relies on
  it), while strings and keys carry none and are freed against the
  cloning allocator explicitly.

## Testing

`tests/` holds the component suite: casting and member access, the
construction path, marshal and quote wire forms, deep-clone
independence, and the release path. The suite is synchronous — the
package has no threads and no clocks. `just test` runs it
single-threaded under the zero-leak log gate; verdicts come from the
log, never the exit status alone.

## Specification

- JSON text follows RFC 8259; the value model is
  `core:encoding/json`'s `Value`, and `json.unparse`'s escape behavior
  on the pinned toolchain is part of this package's wire output.
