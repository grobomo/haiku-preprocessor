#!/bin/bash
# Test: Known shorthand is resolved correctly.
# Verifies: Haiku reads rules, resolves "hook logs", writes analysis with correct path.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
TMP_DIR=$(mktemp -d)
INSTANCE_DIR="$TMP_DIR/instance"
mkdir -p "$INSTANCE_DIR"

# Run preprocessor with a shorthand prompt
RESULT=$(node -e "
var gate = require('$SRC_DIR/preprocessor-gate');
var result = gate.preprocess({
  prompt: 'hook logs',
  instanceDir: '$INSTANCE_DIR',
  rulesPath: '$CONFIG_DIR/rules.yaml.example'
});
console.log(JSON.stringify(result));
" 2>&1)

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "Gate crashed: $RESULT"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Verify action=pass (shorthand should be high confidence)
if ! echo "$RESULT" | grep -q '"action":"pass"'; then
  echo "Expected action:pass, got: $RESULT"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Verify analysis.md was written
if [ ! -f "$INSTANCE_DIR/analysis.md" ]; then
  echo "analysis.md not created"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Verify analysis mentions hook-log.jsonl (the resolved path)
if ! grep -qi "hook-log" "$INSTANCE_DIR/analysis.md"; then
  echo "analysis.md doesn't mention hook-log — shorthand not resolved"
  echo "Content:"
  cat "$INSTANCE_DIR/analysis.md"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Verify analysis.log was appended
if [ ! -f "$INSTANCE_DIR/analysis.log" ]; then
  echo "analysis.log not created (history not tracked)"
  rm -rf "$TMP_DIR"
  exit 1
fi

rm -rf "$TMP_DIR"
exit 0
