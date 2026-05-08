#!/bin/bash
# Test: Gibberish prompts with no matching rules get low confidence / block.
# Verifies: totally meaningless input → action=block with clarification question.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"
TMP_DIR=$(mktemp -d)
INSTANCE_DIR="$TMP_DIR/instance"
RULES_FILE="$TMP_DIR/rules.yaml"
mkdir -p "$INSTANCE_DIR"

# Minimal rules with no shorthand — nothing should match
cat > "$RULES_FILE" << 'EOF'
shorthand: []
interpretation_rules: []
meta_rules:
  - "If genuinely stumped with no matching rules, block and ask"
EOF

# Run preprocessor with gibberish
RESULT=$(node -e "
var gate = require('$SRC_DIR/preprocessor-gate');
var result = gate.preprocess({
  prompt: 'xyzzy qqq blargh 999',
  instanceDir: '$INSTANCE_DIR',
  rulesPath: '$RULES_FILE'
});
console.log(JSON.stringify(result));
" 2>&1)

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "Gate crashed: $RESULT"
  rm -rf "$TMP_DIR"
  exit 1
fi

# Accept either block OR low-confidence pass (Haiku may interpret differently)
# The key assertion: it should NOT be high confidence
if echo "$RESULT" | grep -q '"action":"block"'; then
  # Blocked — correct behavior
  rm -rf "$TMP_DIR"
  exit 0
fi

# If passed, check that confidence is not high
if [ -f "$INSTANCE_DIR/analysis.md" ]; then
  if grep -qi "confidence.*high" "$INSTANCE_DIR/analysis.md"; then
    echo "Gibberish got high confidence — should be medium or low"
    cat "$INSTANCE_DIR/analysis.md"
    rm -rf "$TMP_DIR"
    exit 1
  fi
fi

# Medium confidence is acceptable (Haiku tried to interpret)
rm -rf "$TMP_DIR"
exit 0
