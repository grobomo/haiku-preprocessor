#!/bin/bash
# Test: Conversational confirmations get high confidence, not medium/low.
# Verifies: "ok thanks" → confidence=high in analysis.md.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
TMP_DIR=$(mktemp -d)
INSTANCE_DIR="$TMP_DIR/instance"
mkdir -p "$INSTANCE_DIR"

# Run preprocessor with a simple confirmation
RESULT=$(node -e "
var gate = require('$SRC_DIR/preprocessor-gate');
var result = gate.preprocess({
  prompt: 'ok thanks, looks good',
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

# Verify action=pass
if ! echo "$RESULT" | grep -q '"action":"pass"'; then
  echo "Expected action:pass, got: $RESULT"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Verify confidence=high in analysis.md
if [ ! -f "$INSTANCE_DIR/analysis.md" ]; then
  echo "analysis.md not created"
  rm -rf "$TMP_DIR"
  exit 1
fi

if ! grep -qi "confidence.*high" "$INSTANCE_DIR/analysis.md"; then
  echo "Expected confidence:high for conversational reply"
  echo "Got:"
  grep -i "confidence" "$INSTANCE_DIR/analysis.md"
  rm -rf "$TMP_DIR"
  exit 1
fi

rm -rf "$TMP_DIR"
exit 0
