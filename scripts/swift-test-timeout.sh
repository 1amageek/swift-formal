#!/bin/sh
set -eu
seconds="$1"
shift
if [ "$seconds" -gt 120 ] || [ "$seconds" -lt 1 ]; then
  echo 'Test timeout must be between 1 and 120 seconds.' >&2
  exit 2
fi
exec python3 Tools/run-with-timeout.py --seconds "$seconds" -- swift test "$@"
