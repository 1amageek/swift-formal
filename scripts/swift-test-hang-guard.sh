#!/bin/sh
set -eu
repeats=3
timeout=30
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repeats) repeats="$2"; shift 2 ;;
    --timeout|--build-timeout) timeout="$2"; shift 2 ;;
    --) shift; break ;;
    *) exit 2 ;;
  esac
done
lock=.swift-test-hang-guard.lock
mkdir "$lock" 2>/dev/null || exit 3
trap 'rmdir "$lock"' EXIT HUP INT TERM
scripts/check-sync-shutdown-in-deinit.sh Sources Tests
run=0
while [ "$run" -lt "$repeats" ]; do
  scripts/swift-test-timeout.sh "$timeout" "$@"
  run=$((run+1))
done
