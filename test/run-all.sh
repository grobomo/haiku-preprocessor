#!/bin/bash
# Run all e2e tests for haiku-preprocessor.
# Each test uses a temp directory to avoid contaminating real config.
#
# Prerequisites: HAIKU_ENDPOINT_URL and HAIKU_AUTH_TOKEN (or endpoint accessible)
# Usage: bash test/run-all.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0

run_test() {
  local name="$1"
  local script="$2"
  printf "  %-30s " "$name"
  output=$(bash "$script" 2>&1)
  if [ $? -eq 0 ]; then
    echo "✓ PASS"
    PASS=$((PASS + 1))
  else
    echo "✗ FAIL"
    echo "$output" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Haiku Preprocessor E2E Tests ==="
echo ""
echo "Endpoint: ${HAIKU_ENDPOINT_URL:-http://127.0.0.1:4100/v1/chat/completions}"
echo ""

run_test "haiku-client basic call" "$SCRIPT_DIR/test-haiku-client.sh"
run_test "bypass (! prefix)" "$SCRIPT_DIR/test-bypass.sh"
run_test "shorthand resolution" "$SCRIPT_DIR/test-shorthand.sh"
run_test "conversational (high conf)" "$SCRIPT_DIR/test-conversational.sh"
run_test "gibberish (low conf/block)" "$SCRIPT_DIR/test-block.sh"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
