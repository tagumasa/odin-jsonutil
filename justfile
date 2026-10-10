# odin-jsonutil build tasks. The package lives under src/ (the
# collection is `jsonutil:`); the suite is a separate package in
# tests/ importing it through the collection.

# Show available tasks
default:
	@just --list

# Type-check the package with vet and strict style.
check:
	odin check src/jsonutil -collection:jsonutil=src -vet -strict-style -no-entry-point

# Run the suite single-threaded under the log gate: the runner's own
# exit status is honored first (a compile failure must not read as a
# green run through an empty log), then the verdict is the grep over
# tmp/test.log (zero errors, zero warnings, zero leak lines). grep -a
# because a failing test can spill NUL bytes and silently match
# nothing.
test:
	#!/bin/sh
	set -e
	mkdir -p tmp
	set +e
	odin test tests -collection:jsonutil=src -define:ODIN_TEST_THREADS=1 > tmp/test.log 2>&1
	status=$?
	set -e
	cat tmp/test.log
	if [ "$status" -ne 0 ]; then
		echo "test runner failed (exit $status; see tmp/test.log)" >&2
		exit "$status"
	fi
	if grep -a -E '\[ERROR\]|\[FATAL\]|\[WARN \]|\[WARN\]|\+\+\+ leak|bad free|out of range' tmp/test.log; then
		echo "test log gate failed (see tmp/test.log)" >&2
		exit 1
	fi
