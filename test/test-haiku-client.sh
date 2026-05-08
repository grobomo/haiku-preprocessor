#!/bin/bash
# Test: haiku-client.js can call the LLM endpoint and get a valid response.
# Verifies: curl works, endpoint responds, response is parseable.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")/src"

# Call haiku with a trivial prompt
RESPONSE=$(echo "Reply with exactly the word 'pong' and nothing else." | node "$SRC_DIR/haiku-client.js" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "haiku-client exited with code $EXIT_CODE"
  echo "Output: $RESPONSE"
  exit 1
fi

# Verify response contains something (not empty)
if [ -z "$RESPONSE" ]; then
  echo "Empty response from haiku-client"
  exit 1
fi

# Verify response is not an error message
if echo "$RESPONSE" | grep -qi "ERROR\|failed\|timeout"; then
  echo "Response looks like an error: $RESPONSE"
  exit 1
fi

exit 0
