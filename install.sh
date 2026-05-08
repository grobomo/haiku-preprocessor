#!/bin/bash
set -e

# ┌─────────────────────────────────────────────────────────────────────────┐
# │ HAIKU PREPROCESSOR — Install Script                                      │
# │                                                                         │
# │ Installs the L1 Haiku preprocessor into Claude Code's hook system.      │
# │ Idempotent — safe to run multiple times.                                │
# └─────────────────────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${HOME}/.claude/hooks"
PROXY_DIR="${HOME}/.claude/proxy"
PREPROCESSORS_DIR="${HOOKS_DIR}/preprocessors/user-prompt-submit"
SETTINGS_FILE="${HOME}/.claude/settings.json"

echo "=== Haiku Preprocessor Installer ==="
echo ""

# ─── Prerequisites ────────────────────────────────────────────────────────────

echo "Checking prerequisites..."

if ! command -v node &>/dev/null; then
  echo "ERROR: Node.js not found. Install Node.js >= 18."
  exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  echo "ERROR: Node.js >= 18 required (found v${NODE_VERSION})"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "ERROR: curl not found."
  exit 1
fi

echo "  ✓ Node.js $(node -v)"
echo "  ✓ curl $(curl --version | head -1 | cut -d' ' -f2)"

# ─── Endpoint Configuration ──────────────────────────────────────────────────

echo ""
ENDPOINT_URL="${HAIKU_ENDPOINT_URL:-http://127.0.0.1:4100/v1/chat/completions}"
echo "LLM Endpoint: ${ENDPOINT_URL}"
echo "  (Set HAIKU_ENDPOINT_URL env var to change)"

if [ -n "${HAIKU_AUTH_TOKEN}" ]; then
  echo "  ✓ HAIKU_AUTH_TOKEN is set"
elif [ -n "${ANTHROPIC_AUTH_TOKEN}" ]; then
  echo "  ✓ ANTHROPIC_AUTH_TOKEN is set (will use as fallback)"
else
  echo "  ⚠ No auth token found. Set HAIKU_AUTH_TOKEN or ANTHROPIC_AUTH_TOKEN."
  echo "    The preprocessor will try to read from ~/.claude/settings.json"
fi

# ─── Install Source Files ─────────────────────────────────────────────────────

echo ""
echo "Installing source files..."

mkdir -p "$HOOKS_DIR"
mkdir -p "$PROXY_DIR"
mkdir -p "$PREPROCESSORS_DIR"

cp "$SCRIPT_DIR/src/haiku-client.js" "$HOOKS_DIR/haiku-client.js"
cp "$SCRIPT_DIR/src/preprocessor-gate.js" "$HOOKS_DIR/preprocessor-gate.js"
cp "$SCRIPT_DIR/src/hook-log.js" "$HOOKS_DIR/hook-log.js"

echo "  ✓ haiku-client.js → ${HOOKS_DIR}/"
echo "  ✓ preprocessor-gate.js → ${HOOKS_DIR}/"
echo "  ✓ hook-log.js → ${HOOKS_DIR}/"

# ─── Install Config (don't overwrite existing) ────────────────────────────────

RULES_FILE="${PROXY_DIR}/prompt-preprocessing-rules.yaml"
if [ ! -f "$RULES_FILE" ]; then
  cp "$SCRIPT_DIR/config/rules.yaml.example" "$RULES_FILE"
  echo "  ✓ rules.yaml → ${RULES_FILE}"
else
  echo "  ○ rules.yaml already exists (not overwriting)"
fi

# ─── Install Hook Runner Integration ─────────────────────────────────────────

RUNNER_FILE="${HOOKS_DIR}/run-userpromptsubmit-l1.js"
cat > "$RUNNER_FILE" << 'RUNNER_EOF'
#!/usr/bin/env node
"use strict";
// Hook runner for UserPromptSubmit — invokes L1 preprocessor.
// Installed by haiku-preprocessor/install.sh

var fs = require("fs");
var path = require("path");
var os = require("os");

var HOOKS_DIR = path.join(os.homedir(), ".claude", "hooks");
var PREPROCESSORS_DIR = path.join(HOOKS_DIR, "preprocessors", "user-prompt-submit");
var RULES_PATH = path.join(os.homedir(), ".claude", "proxy", "prompt-preprocessing-rules.yaml");

// Hook input schema:
// { session_id, transcript_path, cwd, permission_mode, hook_event_name, prompt }
var input;
try {
  var raw = process.env.HOOK_INPUT_FILE
    ? fs.readFileSync(process.env.HOOK_INPUT_FILE, "utf-8")
    : fs.readFileSync(0, "utf-8");
  input = JSON.parse(raw);
} catch (e) {
  process.exit(0);
}

var prompt = (input && input.prompt) || (input && input.message) || "";
if (!prompt) process.exit(0);

// Log event to hook-log
var hookLog = require(path.join(HOOKS_DIR, "hook-log"));
hookLog.logEvent("UserPromptSubmit", "l1-preprocessor", "invoke", { preview: prompt.slice(0, 100) });

// Run preprocessor
var gate = require(path.join(HOOKS_DIR, "preprocessor-gate"));
var result;
try {
  result = gate.preprocess({
    prompt: prompt,
    transcriptPath: (input && input.transcript_path) || "",
    sessionId: (input && input.session_id) || "",
    instanceDir: PREPROCESSORS_DIR,
    rulesPath: RULES_PATH
  });
} catch (e) {
  hookLog.logEvent("UserPromptSubmit", "l1-preprocessor", "error", { preview: e.message });
  process.exit(0);
}

// Log result event
hookLog.logEvent("UserPromptSubmit", "l1-preprocessor", result.action === "block" ? "block" : "pass", {
  ms: result.ms,
  confidence: result.confidence,
  preview: prompt.slice(0, 80)
});

// Output
if (result.action === "block") {
  process.stdout.write(JSON.stringify({ decision: "block", reason: result.reason }));
} else if (result.text) {
  process.stdout.write(result.text);
}
process.exit(0);
RUNNER_EOF

echo "  ✓ run-userpromptsubmit-l1.js → ${RUNNER_FILE}"

# ─── Patch settings.json ─────────────────────────────────────────────────────

echo ""
echo "Checking settings.json hook configuration..."

if [ -f "$SETTINGS_FILE" ]; then
  if grep -q "run-userpromptsubmit-l1.js" "$SETTINGS_FILE"; then
    echo "  ○ Hook already configured in settings.json"
  else
    echo "  ⚠ You need to add the UserPromptSubmit hook to ${SETTINGS_FILE}"
    echo "    Add this to the 'hooks' section:"
    echo ""
    echo '    "UserPromptSubmit": ['
    echo '      {'
    echo '        "hooks": ['
    echo '          {'
    echo '            "type": "command",'
    echo '            "command": "node \"$HOME/.claude/hooks/run-userpromptsubmit-l1.js\"",'
    echo '            "timeout": 20'
    echo '          }'
    echo '        ]'
    echo '      }'
    echo '    ]'
    echo ""
  fi
else
  echo "  ⚠ No settings.json found at ${SETTINGS_FILE}"
  echo "    Create one with the hook configuration above."
fi

# ─── Install Cron ─────────────────────────────────────────────────────────────

echo ""
ROTATE_SCRIPT="${HOOKS_DIR}/rotate-preprocessor-logs.sh"
cp "$SCRIPT_DIR/scripts/rotate-audit.sh" "$ROTATE_SCRIPT"
chmod +x "$ROTATE_SCRIPT"

if crontab -l 2>/dev/null | grep -q "rotate-preprocessor-logs"; then
  echo "  ○ Cron already installed"
else
  (crontab -l 2>/dev/null; echo "3 3 * * * ${ROTATE_SCRIPT}") | crontab -
  echo "  ✓ Cron installed (daily log rotation at 3:03am)"
fi

# ─── Connectivity Test ────────────────────────────────────────────────────────

echo ""
echo "Testing endpoint connectivity..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${ENDPOINT_URL%/v1/chat/completions}/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  echo "  ✓ Endpoint reachable (HTTP 200)"
else
  echo "  ⚠ Endpoint not reachable (HTTP ${HTTP_CODE})"
  echo "    Make sure your LLM proxy is running at ${ENDPOINT_URL}"
  echo "    The preprocessor will pass through silently when endpoint is down."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Add your shorthand to: ${RULES_FILE}"
echo "  2. Configure the hook in settings.json (if not already done)"
echo "  3. Run tests: bash $(dirname "$0")/test/run-all.sh"
echo "  4. Restart Claude Code to pick up the new hook"
