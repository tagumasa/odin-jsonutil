// jsonutil component tests: casting and member access, the construction
// path (objects grow through obj_set on a ^map — map literals are
// disabled), the marshal and quote wire forms, deep-clone independence,
// and the release side of the ownership pair — whose assertion is the
// zero-leak log gate: a missed allocation prints a leak block, a wrong
// pointer a bad free.
package tests

import "core:encoding/json"
import "core:mem"
import "core:testing"
import "jsonutil:jsonutil"

// obj_value places a finished map into the value union — the union is
// entered only after the last ^map write.
obj_value :: proc(m: map[string]json.Value) -> json.Value {
	return json.Value(json.Object(m))
}

@(test)
casting_and_member_access :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	obj := jsonutil.json_object(3, a)
	jsonutil.obj_set(&obj, "name", jsonutil.json_string("tools/list"))
	jsonutil.obj_set(&obj, "count", jsonutil.json_int(7))
	jsonutil.obj_set(&obj, "ok", jsonutil.json_bool(true))
	v := obj_value(obj)

	m, is_obj := jsonutil.as_object(v)
	testing.expect_value(t, is_obj, true)
	testing.expect_value(t, len(m), 3)

	if val, ok := jsonutil.obj_get(v, "count"); ok {
		#partial switch x in val {
		case json.Integer:
			testing.expect_value(t, x == 7, true)
		case:
			testing.expectf(t, false, "count is not an integer")
		}
	} else {
		testing.expectf(t, false, "count member missing")
	}

	_, missing := jsonutil.obj_get(v, "nope")
	testing.expect_value(t, missing, false)

	// as_object/as_array answer false outside their own shape.
	_, not_obj := jsonutil.as_object(jsonutil.json_string("x"))
	testing.expect_value(t, not_obj, false)
	arr := jsonutil.json_array({jsonutil.json_int(1), jsonutil.json_int(2)}, a)
	_, arr_as_obj := jsonutil.as_object(arr)
	testing.expect_value(t, arr_as_obj, false)
	_, obj_as_arr := jsonutil.as_array(v)
	testing.expect_value(t, obj_as_arr, false)

	sl, is_arr := jsonutil.as_array(arr)
	testing.expect_value(t, is_arr, true)
	testing.expect_value(t, len(sl), 2)

	// obj_get_bool reads only boolean members: true for one, false for
	// an absent key and for a member of another type.
	testing.expect_value(t, jsonutil.obj_get_bool(v, "ok"), true)
	testing.expect_value(t, jsonutil.obj_get_bool(v, "count"), false)
	testing.expect_value(t, jsonutil.obj_get_bool(v, "nope"), false)
}

@(test)
construction_enters_whole_objects :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	obj := jsonutil.json_object(2, a)
	sub := jsonutil.json_object(1, a)
	jsonutil.obj_set(&sub, "deep", jsonutil.json_bool(true))
	jsonutil.obj_set_object(&obj, "params", sub)
	jsonutil.obj_set(&obj, "name", jsonutil.json_string("x"))
	v := obj_value(obj)

	// The entered sub-object reads back whole: filling went through the
	// ^map, and the union was entered after the last write.
	params, ok := jsonutil.obj_get(v, "params")
	pm, is_obj := jsonutil.as_object(params)
	testing.expect_value(t, ok && is_obj, true)
	testing.expect_value(t, len(pm), 1)
	testing.expect_value(t, jsonutil.obj_get_bool(params, "deep"), true)
}

@(test)
marshal_wire_forms :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	// Scalars and arrays marshal to their exact wire bytes.
	testing.expect_value(t, jsonutil.marshal_value_unsorted(jsonutil.json_int(42), a), "42")
	testing.expect_value(t, jsonutil.marshal_value_unsorted(jsonutil.json_bool(false), a), "false")
	testing.expect_value(t, jsonutil.marshal_value_unsorted(jsonutil.json_string("s"), a), "\"s\"")
	testing.expect_value(t, jsonutil.marshal_value_unsorted(nil, a), "null")
	arr := jsonutil.json_array({jsonutil.json_int(1), jsonutil.json_int(2)}, a)
	testing.expect_value(t, jsonutil.marshal_value_unsorted(arr, a), "[1,2]")

	// A multi-member object marshals in its map's iteration order, so
	// the check is a parse round-trip member by member — not byte
	// equality. parse_integers=true: the default parses numbers as
	// Floats.
	obj := jsonutil.json_object(2, a)
	jsonutil.obj_set(&obj, "name", jsonutil.json_string("tools/call"))
	jsonutil.obj_set(&obj, "retries", jsonutil.json_int(2))
	out := jsonutil.marshal_value_unsorted(obj_value(obj), a)
	parsed, perr := json.parse_string(out, parse_integers = true, allocator = a)
	testing.expect_value(t, perr == .None, true)
	if name, ok := jsonutil.obj_get(parsed, "name"); ok {
		#partial switch s in name {
		case json.String:
			testing.expect_value(t, string(s) == "tools/call", true)
		case:
			testing.expectf(t, false, "name is not a string")
		}
	} else {
		testing.expectf(t, false, "name member missing after round-trip")
	}
	if retries, ok := jsonutil.obj_get(parsed, "retries"); ok {
		#partial switch x in retries {
		case json.Integer:
			testing.expect_value(t, x == 2, true)
		case:
			testing.expectf(t, false, "retries is not an integer")
		}
	} else {
		testing.expectf(t, false, "retries member missing after round-trip")
	}

	// Escapes survive the marshal round-trip.
	esc := "a\"b\\c\nd月"
	parsed_esc, perr_esc := json.parse_string(jsonutil.marshal_value_unsorted(jsonutil.json_string(esc), a), allocator = a)
	testing.expect_value(t, perr_esc == .None, true)
	#partial switch s2 in parsed_esc {
	case json.String:
		testing.expect_value(t, string(s2) == esc, true)
	case:
		testing.expectf(t, false, "escaped input did not parse to a string")
	}
}

@(test)
clone_value_is_deep :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	sa := mem.dynamic_arena_allocator(&arena)

	obj := jsonutil.json_object(2, sa)
	jsonutil.obj_set(&obj, "name", jsonutil.json_string("tool"))
	jsonutil.obj_set(&obj, "tags", jsonutil.json_array({jsonutil.json_string("a"), jsonutil.json_string("b")}, sa))
	sv := obj_value(obj)

	cv := jsonutil.clone_value(sv, context.allocator)

	// The clone's string bytes are its own: writing through the clone
	// leaves the source value untouched (the source string is a literal
	// — its bytes cannot move).
	nm, _ := jsonutil.obj_get(cv, "name")
	#partial switch s in nm {
	case json.String:
		sp := string(s)
		bytes := transmute([]u8)sp
		bytes[0] = 'T'
	case:
	}
	orig_nm, _ := jsonutil.obj_get(sv, "name")
	#partial switch s2 in orig_nm {
	case json.String:
		testing.expect_value(t, string(s2) == "tool", true)
	case:
	}
	clone_nm, _ := jsonutil.obj_get(cv, "name")
	#partial switch s3 in clone_nm {
	case json.String:
		testing.expect_value(t, string(s3) == "Tool", true)
	case:
	}

	// Scalars pass through unchanged; nil clones to nil.
	testing.expect_value(t, jsonutil.marshal_value_unsorted(jsonutil.clone_value(jsonutil.json_int(5), context.allocator), sa), "5")
	testing.expect_value(t, jsonutil.clone_value(nil, context.allocator) == nil, true)

	jsonutil.free_value(cv, context.allocator)
}

@(test)
free_value_releases_the_whole_clone :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	sa := mem.dynamic_arena_allocator(&arena)

	root := jsonutil.json_object(3, sa)
	jsonutil.obj_set(&root, "name", jsonutil.json_string("tools/call"))
	args := jsonutil.json_object(2, sa)
	jsonutil.obj_set(&args, "cmd", jsonutil.json_string("grep"))
	jsonutil.obj_set(&args, "flags", jsonutil.json_array({jsonutil.json_string("-i"), jsonutil.json_int(3)}, sa))
	jsonutil.obj_set_object(&root, "arguments", args)
	jsonutil.obj_set(&root, "ok", jsonutil.json_bool(true))
	sv := obj_value(root)

	cv := jsonutil.clone_value(sv, context.allocator)

	// The clone carries the whole tree member for member.
	args_v, ok := jsonutil.obj_get(cv, "arguments")
	testing.expect_value(t, ok, true)
	flags_v, ok2 := jsonutil.obj_get(args_v, "flags")
	testing.expect_value(t, ok2, true)
	sl, is_arr := jsonutil.as_array(flags_v)
	testing.expect_value(t, is_arr && len(sl) == 2, true)
	cmd_v, ok3 := jsonutil.obj_get(args_v, "cmd")
	testing.expect_value(t, ok3, true)
	#partial switch s in cmd_v {
	case json.String:
		testing.expect_value(t, string(s) == "grep", true)
	case:
		testing.expectf(t, false, "cmd is not a string")
	}

	// Scalars and null are legal no-op frees.
	jsonutil.free_value(jsonutil.json_int(1), context.allocator)
	jsonutil.free_value(nil, context.allocator)

	// The deep release: any allocation clone_value made and free_value
	// missed shows up as a leak block in the log gate; any pointer it
	// frees twice, as a bad free.
	jsonutil.free_value(cv, context.allocator)
}

@(test)
json_quote_renders_valid_literals :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	testing.expect_value(t, jsonutil.json_quote("", a) == "\"\"", true)
	testing.expect_value(t, jsonutil.json_quote("\n\r\t", a) == `"\n\r\t"`, true)
	testing.expect_value(t, jsonutil.json_quote("\"\\", a) == `"\"\\"`, true)
	// C0 controls escape as \u00xx with lowercase hex.
	testing.expect_value(t, jsonutil.json_quote("\x01\x0F\x1F", a) == `"\u0001\u000f\u001f"`, true)
	testing.expect_value(t, jsonutil.json_quote("a\x01b", a) == `"a\u0001b"`, true)
	// Valid non-ASCII passes through as its own UTF-8 bytes.
	testing.expect_value(t, jsonutil.json_quote("月", a) == `"月"`, true)

	// A raw invalid byte (0xFF) becomes U+FFFD — the literal still
	// yields a valid JSON string.
	raw := make([]u8, 2, a)
	raw[0] = 0xFF
	raw[1] = 'x'
	bad := transmute(string)raw
	testing.expect_value(t, jsonutil.json_quote(bad, a) == "\"\uFFFDx\"", true)

	// Every quoted form parses back to the input's runes (invalid
	// bytes decoded to U+FFFD).
	Quote_Case :: struct {
		s:    string,
		want: string,
	}
	cases: []Quote_Case = {
		{"plain", "plain"},
		{"a\"b\\c\nd月", "a\"b\\c\nd月"},
		{bad, "\uFFFDx"},
	}
	for c in cases {
		parsed, perr := json.parse_string(jsonutil.json_quote(c.s, a), allocator = a)
		testing.expectf(t, perr == .None, "quoted form failed to parse: %s", jsonutil.json_quote(c.s, a))
		#partial switch x in parsed {
		case json.String:
			testing.expect_value(t, string(x) == c.want, true)
		case:
			testing.expectf(t, false, "quoted form did not parse to a string: %s", c.s)
		}
	}
}

@(test)
values_equal_compares_semantics :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	// Objects compare by key set regardless of member order.
	ab := jsonutil.json_object(2, a)
	jsonutil.obj_set(&ab, "x", jsonutil.json_int(1))
	jsonutil.obj_set(&ab, "y", jsonutil.json_string("s"))
	ba := jsonutil.json_object(2, a)
	jsonutil.obj_set(&ba, "y", jsonutil.json_string("s"))
	jsonutil.obj_set(&ba, "x", jsonutil.json_int(1))
	testing.expect(t, jsonutil.values_equal(obj_value(ab), obj_value(ba)))

	// Containers compare recursively.
	inner_a := jsonutil.json_object(1, a)
	jsonutil.obj_set(&inner_a, "k", jsonutil.json_bool(false))
	inner_b := jsonutil.json_object(1, a)
	jsonutil.obj_set(&inner_b, "k", jsonutil.json_bool(false))
	outer_a := jsonutil.json_object(1, a)
	jsonutil.obj_set_object(&outer_a, "in", inner_a)
	outer_b := jsonutil.json_object(1, a)
	jsonutil.obj_set_object(&outer_b, "in", inner_b)
	testing.expect(t, jsonutil.values_equal(obj_value(outer_a), obj_value(outer_b)))

	// Key-set mismatches fail in either direction.
	small := jsonutil.json_object(1, a)
	jsonutil.obj_set(&small, "x", jsonutil.json_int(1))
	big := jsonutil.json_object(2, a)
	jsonutil.obj_set(&big, "x", jsonutil.json_int(1))
	jsonutil.obj_set(&big, "z", jsonutil.json_int(2))
	testing.expect(t, !jsonutil.values_equal(obj_value(small), obj_value(big)))
	testing.expect(t, !jsonutil.values_equal(obj_value(big), obj_value(small)))

	// Scalars compare by kind first: 1, "1", and true are three different
	// values, and Integer never equals a Float of the same numeric value —
	// the JSON literals differ textually.
	testing.expect(t, jsonutil.values_equal(jsonutil.json_int(1), jsonutil.json_int(1)))
	testing.expect(t, !jsonutil.values_equal(jsonutil.json_int(1), jsonutil.json_string("1")))
	testing.expect(t, !jsonutil.values_equal(jsonutil.json_int(1), jsonutil.json_bool(true)))
	testing.expect(t, !jsonutil.values_equal(jsonutil.json_int(1), json.Float(1.0)))
	testing.expect(t, jsonutil.values_equal(json.Float(1.5), json.Float(1.5)))
	testing.expect(t, jsonutil.values_equal(jsonutil.json_string("a"), jsonutil.json_string("a")))
	testing.expect(t, !jsonutil.values_equal(jsonutil.json_string("a"), jsonutil.json_string("b")))
	testing.expect(t, jsonutil.values_equal(json.Null{}, json.Null{}))
	testing.expect(t, !jsonutil.values_equal(json.Null{}, jsonutil.json_int(0)))

	// Array comparison is ordered and length-sensitive.
	arr12 := jsonutil.json_array({jsonutil.json_int(1), jsonutil.json_int(2)}, a)
	arr21 := jsonutil.json_array({jsonutil.json_int(2), jsonutil.json_int(1)}, a)
	arr1 := jsonutil.json_array({jsonutil.json_int(1)}, a)
	testing.expect(t, !jsonutil.values_equal(arr12, arr21))
	testing.expect(t, !jsonutil.values_equal(arr12, arr1))
	testing.expect(t, jsonutil.values_equal(arr12, jsonutil.json_array({jsonutil.json_int(1), jsonutil.json_int(2)}, a)))

	// An object never equals an array.
	testing.expect(t, !jsonutil.values_equal(obj_value(ab), arr12))
}

@(test)
marshal_value_sorts_keys :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	// Byte-exact JSON in expect() comparisons only — never through
	// expect_value/expectf, whose fmt layer reads braces in the rendered
	// string as parameter markers.

	// The sorted form orders keys no matter the insertion order.
	m := jsonutil.json_object(3, a)
	jsonutil.obj_set(&m, "zebra", jsonutil.json_int(1))
	jsonutil.obj_set(&m, "alpha", jsonutil.json_string("x"))
	jsonutil.obj_set(&m, "mid", jsonutil.json_bool(true))
	testing.expect(t, jsonutil.marshal_value(obj_value(m), a) ==
		"{\"alpha\":\"x\",\"mid\":true,\"zebra\":1}")

	// Scalars, empties, and nesting render exactly.
	testing.expect(t, jsonutil.marshal_value(jsonutil.json_int(42), a) == "42")
	// Floats render through core json's fixed-precision writer ('f' mode,
	// 16 fractional digits) — pinned as-is: the format is the core's
	// choice, surfaced through this wrapper unchanged.
	testing.expect(t, jsonutil.marshal_value(json.Float(1.5), a) == "1.5000000000000000")
	testing.expect(t, jsonutil.marshal_value(jsonutil.json_bool(false), a) == "false")
	testing.expect(t, jsonutil.marshal_value(json.Null{}, a) == "null")
	testing.expect(t, jsonutil.marshal_value(obj_value(jsonutil.json_object(0, a)), a) == "{}")
	testing.expect(t, jsonutil.marshal_value(jsonutil.json_array(nil, a), a) == "[]")
	testing.expect(t, jsonutil.marshal_value(jsonutil.json_string("a\"b\\c\nd"), a) == "\"a\\\"b\\\\c\\nd\"")

	nested_in := jsonutil.json_object(1, a)
	jsonutil.obj_set(&nested_in, "b", jsonutil.json_array(
		{jsonutil.json_int(1), json.Null{}, jsonutil.json_bool(true), jsonutil.json_string("x")},
		a,
	))
	nested := jsonutil.json_object(1, a)
	jsonutil.obj_set_object(&nested, "a", nested_in)
	testing.expect(t, jsonutil.marshal_value(obj_value(nested), a) ==
		"{\"a\":{\"b\":[1,null,true,\"x\"]}}")
}

@(test)
json_string_array_builds_in_place :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	strs := jsonutil.json_string_array({"beta", "alpha"}, a)
	testing.expect(t, jsonutil.marshal_value(strs, a) == "[\"beta\",\"alpha\"]")
	if arr, ok := jsonutil.as_array(strs); ok {
		testing.expect_value(t, len(arr), 2)
		testing.expect_value(t, jsonutil.value_str(arr[0]), "beta")
	} else {
		testing.expectf(t, ok, "string array should cast")
	}
	testing.expect(t, jsonutil.marshal_value(jsonutil.json_string_array(nil, a), a) == "[]")
}

@(test)
typed_accessors_default_on_wrong_kind :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	a := mem.dynamic_arena_allocator(&arena)

	obj := jsonutil.json_object(3, a)
	jsonutil.obj_set(&obj, "flag", jsonutil.json_bool(true))
	jsonutil.obj_set(&obj, "name", jsonutil.json_string("x"))
	jsonutil.obj_set(&obj, "count", jsonutil.json_int(1))
	v := obj_value(obj)

	// obj_get_bool reads false for absent AND non-bool members.
	testing.expect(t, jsonutil.obj_get_bool(v, "flag"))
	testing.expect(t, !jsonutil.obj_get_bool(v, "nope"))
	testing.expect(t, !jsonutil.obj_get_bool(v, "name"))
	testing.expect(t, !jsonutil.obj_get_bool(v, "count"))

	// value_str reads "" for anything but a String; obj_get_int reads 0
	// for absent and non-integer members.
	name, ok := jsonutil.obj_get(v, "name")
	testing.expect(t, ok)
	testing.expect_value(t, jsonutil.value_str(name), "x")
	count, _ := jsonutil.obj_get(v, "count")
	testing.expect_value(t, jsonutil.value_str(count), "")
	missing, mok := jsonutil.obj_get(v, "nope")
	testing.expect(t, !mok)
	testing.expect_value(t, jsonutil.value_str(missing), "")
	testing.expect_value(t, jsonutil.value_int(count), 1)
	testing.expect_value(t, jsonutil.obj_get_int(v, "count"), 1)
	testing.expect_value(t, jsonutil.obj_get_int(v, "name"), 0)
	testing.expect_value(t, jsonutil.obj_get_int(v, "nope"), 0)
	testing.expect_value(t, jsonutil.value_bool(jsonutil.json_bool(false)), false)
}

@(test)
json_quote_bytes_preserves_source_bytes :: proc(t: ^testing.T) {
	// On valid UTF-8 the two quote forms render byte-identical output,
	// named escapes and C0 \u00XX included.
	same := "a\tb\rc\"d\\e\x0bf"
	bq := jsonutil.json_quote_bytes(same, context.allocator)
	rq := jsonutil.json_quote(same, context.allocator)
	testing.expect(t, bq == rq)
	delete(bq)
	delete(rq)

	// Invalid UTF-8 passes through byte-for-byte instead of becoming
	// U+FFFD — the byte-record form keeps the source bytes.
	broken := "x\xFFy"
	got := jsonutil.json_quote_bytes(broken, context.allocator)
	testing.expect(t, got == "\"x\xFFy\"")
	delete(got)

	// The sanitizing form replaces the broken byte with U+FFFD.
	sanitized := jsonutil.json_quote(broken, context.allocator)
	testing.expect(t, sanitized == "\"x\xEF\xBF\xBDy\"")
	delete(sanitized)
}
