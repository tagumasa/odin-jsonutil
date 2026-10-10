# odin-jsonutil

The JSON value layer for Odin: casting and member access
(`as_object`/`as_array`/`obj_get`), the construction helpers that
replace map literals (`json_object` + `obj_set`), the wire serializer
(`marshal_value_unsorted`), the deep-clone/release pair
(`clone_value`/`free_value`) that moves a value across a lifetime
boundary, and `json_quote` — which renders any string, broken UTF-8
included, as a valid JSON string literal. Pure Odin on `core:*`, zero
foreign imports; every allocation is explicit and caller-owned.

[odin-jsonrpc](https://github.com/tagumasa/odin-jsonrpc) builds its
wire faces on these helpers — the envelope, the pending table, and the
request queue all marshal and clone through this package; any host
holding `core:encoding/json` values can take it directly.

The specification — the value model, construction and marshaling
rules, clone/free ownership — is [docs/design.md](docs/design.md).

## Layout

```
src/jsonutil/  the value layer (the whole library)
tests/         the component suite (just test; zero-leak log gate)
docs/          design.md and the documentation index
justfile       the gates: check, test
.github/       pinned-toolchain CI (Linux, macOS, Windows)
AGENTS.md      rules and policy for coding agents
LICENCE.md     MIT
```

Consumers mount this tree as the `jsonutil:` collection
(`-collection:jsonutil=<path-to-src>`).

## Building values

Map literals are disabled in this codebase: a map value copied out of
a `json.Value` carries its own header, so writes go through a `^map`
and the value union is entered only after the last write:

```odin
import "core:mem"
import "jsonutil:jsonutil" // -collection:jsonutil=<path-to-src>

arena: mem.Dynamic_Arena
mem.dynamic_arena_init(&arena, context.allocator)
defer mem.dynamic_arena_destroy(&arena)
a := mem.dynamic_arena_allocator(&arena)

params := jsonutil.json_object(2, a)
jsonutil.obj_set(&params, "name", jsonutil.json_string("grep"))
flags := jsonutil.json_array({jsonutil.json_string("-i")}, a)
jsonutil.obj_set(&params, "flags", flags)

body := jsonutil.marshal_value_unsorted(jsonutil.json.Value(json.Object(params)), a)
```

`marshal_value_unsorted` skips the per-object key sort — object keys
appear in the map's iteration order, which the wire allows; a caller
that needs deterministic bytes sorts keys on its own side.

## Crossing lifetime boundaries

A parsed value lives in its parse arena. The moment something must
outlive that arena — a table entry, a queued request, a reply slot —
it crosses through `clone_value`, which deep-copies strings, arrays,
and maps (keys included) into the destination allocator, and the owner
releases it with `free_value`. Never hand out pointers into a foreign
arena.

## Quick start

```sh
git clone https://github.com/tagumasa/odin-jsonutil
cd odin-jsonutil
just check         # odin check -vet -strict-style over the package
just test          # serial suite; verdicts from the log, zero leak lines
```

`just check` and `just test` are self-contained: the Odin compiler and
`just` are the whole setup.

## Requirements

- The Odin compiler, nightly `dev-2026-10-nightly:84bc3fc` (the
  frozen `dev-2026-10` release; the gates are re-run after toolchain
  moves)
- `just` (any recent version); on Windows the `sh`-scripted `test`
  recipe needs Git Bash's `sh` on PATH — the CI runner image carries it

## Licence

MIT — see [LICENCE.md](LICENCE.md).
