#!/bin/sh
# Runs the FitnessCore tests (the coaching logic) on this Mac, no simulator needed.
# With Xcode installed this is a plain `swift test`; with only Apple's Command
# Line Tools, Swift Testing's macros need their plugin path passed in.
cd "$(dirname "$0")/../Packages/FitnessCore" || exit 1
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
