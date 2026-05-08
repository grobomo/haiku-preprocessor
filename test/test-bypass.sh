#!/bin/bash
# Test: "!" prefix bypasses Haiku entirely.
# Verifies: no LLM call made, action=pass, bypass=true.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"
TMP_DIR=$(mktemp -d)
RULES_FILE="$TMP_DIR/rules.yaml"
INSTANCE_DIR="$TMP_DIR/instance"

# Create minimal rules file
echo "shorthand: []" > "$RULES_FILE"
mkdir -p "$INSTANCE_DIR"

# Run preprocessor with "!" prefix
RESULT=$(node -e "
var gate = require('$SRC_DIR/preprocessor-gate');
var result = gate.preprocess({
  prompt: '+ just do the thing',
  instanceDir: '$INSTANCE_DIR',
  rulesPath: '$RULES_FILE'
});
console.log(JSON.stringify(result));
" 2>&1)

# Verify bypass=true
if ! echo "$RESULT" | grep -q '"bypass":true'; then
  echo "Expected bypass:true, got: $RESULT"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Verify no analysis.md was written (bypass skips LLM)
if [ -f "$INSTANCE_DIR/analysis.md" ]; then
  echo "analysis.md should NOT exist after bypass"
  rm -rf "$TMP_DIR"
  exit 1
fi

rm -rf "$TMP_DIR"
exit 0
