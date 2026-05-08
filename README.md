# Haiku Preprocessor

A Claude Code hook that runs Haiku (or any fast LLM) on every user prompt before the main model processes it. Acts as an L1 triage layer — resolves shorthand, detects ambiguity, enriches context.

## Architecture

```
User types message
       │
       ├── starts with "+" → BYPASS (raw to main model, no L1)
       │
       ▼
preprocessor-gate.js
       │
  ┌────┴────┐
  │  Read   │  rules.yaml (shorthand + interpretation rules)
  │  Read   │  transcript (last 10 turns for context)
  └────┬────┘
       │
       ▼
  haiku-client.js → LLM endpoint (OpenAI-compatible)
       │
       ▼
  Haiku returns: { confidence, notes, shorthand_resolved, question }
       │
  ┌────┴─────────────────────────────────────────────┐
  │ high confidence → pass, write analysis            │
  │ medium         → pass, flag "ask before acting"   │
  │ low            → block, ask user in TUI directly  │
  └──────────────────────────────────────────────────┘
       │
       ▼
  Instance directory:
    analysis.md   ← latest (main model reads this)
    analysis.log  ← appending history (for audit)
```

## Prerequisites

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Node.js | >= 18 | Runs hook scripts |
| curl | any | HTTP calls to LLM endpoint |
| LLM endpoint | OpenAI-compatible | `/v1/chat/completions` API |
| Claude Code | >= 2.0 | Hook system (UserPromptSubmit) |
| cron | any (optional) | Log rotation |

**No npm packages.** Pure Node.js built-ins only.

## Quick Start

```bash
# 1. Clone
git clone https://github.com/grobomo/haiku-preprocessor.git
cd haiku-preprocessor

# 2. Set your endpoint (any OpenAI-compatible LLM API)
export HAIKU_ENDPOINT_URL="http://127.0.0.1:4100/v1/chat/completions"
export HAIKU_AUTH_TOKEN="your-bearer-token"

# 3. Install
bash install.sh

# 4. Test
bash test/run-all.sh

# 5. Restart Claude Code
```

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `HAIKU_ENDPOINT_URL` | `http://127.0.0.1:4100/v1/chat/completions` | LLM endpoint URL |
| `HAIKU_AUTH_TOKEN` | (none) | Bearer token for endpoint |
| `HAIKU_MODEL` | `claude-4.5-haiku` | Model ID to use |
| `ANTHROPIC_AUTH_TOKEN` | (none) | Fallback token (if HAIKU_AUTH_TOKEN unset) |

### Rules YAML

Edit `~/.claude/proxy/prompt-preprocessing-rules.yaml` to customize:

```yaml
shorthand:
  - pattern: "deploy status"
    means: "Check CI/CD pipeline status for current branch"
  - pattern: "pr comments"
    means: "Read GitHub PR review comments on current branch"

interpretation_rules:
  - name: my-custom-rule
    check: "Does the prompt reference a Jira ticket?"
    action: "Resolve to the Jira URL and include ticket summary"

meta_rules:
  - "If user mentions a teammate by first name, resolve to their GitHub handle"
```

Changes take effect immediately — the file is read fresh on every prompt.

### Feedback Loop

The main model (Opus/Sonnet) can teach L1 by editing the rules YAML directly:
- Discovers new shorthand → appends to `shorthand:` section
- Learns interpretation patterns → adds to `interpretation_rules:`
- Any new section added to the YAML is immediately available to L1

## Per-Instance Logging

Each preprocessor instance maintains its own analysis files:

```
~/.claude/hooks/preprocessors/
  user-prompt-submit/
    analysis.md     ← latest analysis (main model reads this)
    analysis.log    ← timestamped history of all analyses
  pre-tool-use/     ← (if you add one for pre-tool-use)
    analysis.md
    analysis.log
```

The global `hook-log.jsonl` only gets events (fired/pass/block/ms) — no analysis text.

## Standalone Usage

`haiku-client.js` works independently of the hook system:

```bash
# CLI
echo "What does this error mean?" | node src/haiku-client.js

# JSON mode (structured response)
node src/haiku-client.js --prompt "Classify this: deploy to prod" --json

# From scripts
node -e "
var haiku = require('./src/haiku-client');
var result = haiku.call({ prompt: 'hello', jsonMode: true });
console.log(result.ok ? result.parsed : result.error);
"
```

## Safety

- **`+` bypass**: Any message starting with `+` skips L1 entirely
- **Timeout passthrough**: If Haiku fails or times out, prompt passes through (never blocks)
- **Max 3 consecutive blocks**: After 3 blocks in a row, forces passthrough
- **No secrets in code**: Auth token comes from environment at runtime

## Testing

```bash
# Run all tests (requires endpoint to be reachable)
bash test/run-all.sh

# Individual tests
bash test/test-haiku-client.sh     # Basic LLM call works
bash test/test-bypass.sh           # "+" prefix skips LLM
bash test/test-shorthand.sh        # Known shorthand resolved
bash test/test-conversational.sh   # Confirmations → high confidence
bash test/test-block.sh            # Gibberish → low confidence
```

## File Structure

```
haiku-preprocessor/
├── README.md
├── install.sh              # One-command setup
├── src/
│   ├── haiku-client.js     # Shared LLM caller (standalone or require())
│   ├── preprocessor-gate.js # Analysis logic + instance-scoped logging
│   └── hook-log.js         # Event-only logger for hook-log.jsonl
├── config/
│   ├── rules.yaml.example  # Starting rules template
│   └── session-start-instructions.md.example
├── scripts/
│   └── rotate-audit.sh     # Daily log rotation (cron)
├── test/
│   ├── run-all.sh
│   ├── test-haiku-client.sh
│   ├── test-bypass.sh
│   ├── test-shorthand.sh
│   ├── test-conversational.sh
│   └── test-block.sh
└── .github/
    ├── publish.json
    └── workflows/secret-scan.yml
```

## License

MIT
