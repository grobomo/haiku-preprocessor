#!/usr/bin/env node
"use strict";
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ HAIKU CLIENT — Shared LLM interface for hook preprocessors              │
// │                                                                         │
// │ Any hook or standalone process can require() this to call Haiku.        │
// │ Each caller provides an instanceDir where analysis is stored.           │
// │                                                                         │
// │ Logging architecture:                                                   │
// │   - Analysis text → instanceDir/analysis.md (latest, for consumer)      │
// │   - Analysis history → instanceDir/analysis.log (appending, for audit)  │
// │   - Events only → global hook-log.jsonl (fired/pass/block/ms)           │
// │                                                                         │
// │ Usage:                                                                  │
// │   var haiku = require("./haiku-client");                                │
// │   var result = haiku.call({ prompt: "...", instanceDir: "/path/..." }); │
// │                                                                         │
// │ CLI:                                                                    │
// │   echo "prompt" | node haiku-client.js                                  │
// │   node haiku-client.js --prompt "prompt" --json                         │
// │                                                                         │
// │ Environment:                                                            │
// │   HAIKU_ENDPOINT_URL  — LLM endpoint (default: http://127.0.0.1:4100)  │
// │   HAIKU_AUTH_TOKEN    — Bearer token for endpoint                       │
// │   HAIKU_MODEL         — Model ID (default: claude-4.5-haiku)            │
// │                                                                         │
// │ Dependencies: Node.js >= 18, curl                                       │
// │ No npm packages required.                                               │
// └─────────────────────────────────────────────────────────────────────────┘

var fs = require("fs");
var path = require("path");
var child_process = require("child_process");

// ─── Configuration ───────────────────────────────────────────────────────────

var DEFAULT_CONFIG = {
  endpointUrl: process.env.HAIKU_ENDPOINT_URL || "http://127.0.0.1:4100/v1/chat/completions",
  model: process.env.HAIKU_MODEL || "claude-4.5-haiku",
  maxTokens: 500,
  timeoutMs: 12000
};

// ─── Auth Token Resolution ───────────────────────────────────────────────────

var _cachedToken = null;

function getAuthToken() {
  if (_cachedToken) return _cachedToken;

  if (process.env.HAIKU_AUTH_TOKEN) {
    _cachedToken = process.env.HAIKU_AUTH_TOKEN;
    return _cachedToken;
  }
  if (process.env.ANTHROPIC_AUTH_TOKEN) {
    _cachedToken = process.env.ANTHROPIC_AUTH_TOKEN;
    return _cachedToken;
  }

  // Fallback: read from ~/.claude/settings.json
  try {
    var settingsPath = path.join(process.env.HOME || "", ".claude", "settings.json");
    var settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
    var token = (settings.env && (settings.env.HAIKU_AUTH_TOKEN || settings.env.ANTHROPIC_AUTH_TOKEN)) || "";
    if (token) { _cachedToken = token; return _cachedToken; }
  } catch (e) {}

  return "";
}

// ─── Instance Logging ────────────────────────────────────────────────────────

// writeAnalysis(instanceDir, content)
// Writes latest analysis to instanceDir/analysis.md (overwritten)
// Appends timestamped entry to instanceDir/analysis.log (history)
function writeAnalysis(instanceDir, content) {
  if (!instanceDir) return;
  try {
    fs.mkdirSync(instanceDir, { recursive: true });
    fs.writeFileSync(path.join(instanceDir, "analysis.md"), content, "utf-8");
    fs.appendFileSync(path.join(instanceDir, "analysis.log"),
      "\n---\n" + content + "\n", "utf-8");
  } catch (e) {}
}

// ─── Core: Call Haiku ────────────────────────────────────────────────────────

// call(options)
//
// Options:
//   prompt       — string (required): the full prompt to send
//   system       — string (optional): system message
//   maxTokens    — number (optional): max response tokens (default: 500)
//   timeoutMs    — number (optional): timeout in ms (default: 12000)
//   model        — string (optional): model override
//   jsonMode     — boolean (optional): parse response as JSON
//   instanceDir  — string (optional): directory for analysis.md/analysis.log
//   caller       — string (optional): module name for event logging
//
// Returns:
//   { ok: true, content: string, parsed?: object, ms: number }
//   { ok: false, error: string, ms: number }

function call(options) {
  if (!options || !options.prompt) {
    return { ok: false, error: "missing prompt", ms: 0 };
  }

  var endpointUrl = options.endpointUrl || DEFAULT_CONFIG.endpointUrl;
  var model = options.model || DEFAULT_CONFIG.model;
  var maxTokens = options.maxTokens || DEFAULT_CONFIG.maxTokens;
  var timeoutMs = options.timeoutMs || DEFAULT_CONFIG.timeoutMs;
  var curlTimeout = Math.ceil(timeoutMs / 1000);
  var token = getAuthToken();

  var messages = [];
  if (options.system) {
    messages.push({ role: "system", content: options.system });
  }
  messages.push({ role: "user", content: options.prompt });

  var requestBody = JSON.stringify({
    model: model,
    messages: messages,
    max_tokens: maxTokens
  });

  var start = Date.now();
  var rawResponse;
  try {
    rawResponse = child_process.execSync(
      'curl -s --max-time ' + curlTimeout +
      ' "' + endpointUrl + '"' +
      ' -H "Content-Type: application/json"' +
      ' -H "Authorization: Bearer ' + token + '"' +
      ' -d @-',
      { input: requestBody, encoding: "utf-8", timeout: timeoutMs + 2000, stdio: ["pipe", "pipe", "pipe"] }
    ).trim();
  } catch (e) {
    var ms = Date.now() - start;
    return { ok: false, error: "curl failed: " + e.message.slice(0, 100), ms: ms };
  }
  var ms = Date.now() - start;

  // Parse OpenAI-format response
  var content;
  try {
    var response = JSON.parse(rawResponse);
    if (response.error) {
      return { ok: false, error: "API error: " + JSON.stringify(response.error).slice(0, 150), ms: ms };
    }
    content = response.choices[0].message.content;
  } catch (e) {
    return { ok: false, error: "response parse failed", ms: ms };
  }

  // Optionally parse as JSON
  var parsed = null;
  if (options.jsonMode) {
    var jsonMatch = content.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      try { parsed = JSON.parse(jsonMatch[0]); } catch (e) {}
    }
    if (!parsed) {
      return { ok: false, error: "json parse failed in response", content: content, ms: ms };
    }
  }

  var result = { ok: true, content: content, ms: ms };
  if (parsed) result.parsed = parsed;
  return result;
}

// ─── Transcript Context Helper ───────────────────────────────────────────────

// readTranscriptContext(transcriptPath, maxTurns)
// Reads last N turns from a Claude Code session transcript JSONL.
function readTranscriptContext(transcriptPath, maxTurns) {
  maxTurns = maxTurns || 10;
  if (!transcriptPath) return "";

  try {
    if (!fs.existsSync(transcriptPath)) return "";
    var lines = fs.readFileSync(transcriptPath, "utf-8").trim().split("\n");
    var turns = [];
    var startIdx = Math.max(0, lines.length - (maxTurns * 6));
    for (var i = startIdx; i < lines.length && turns.length < maxTurns; i++) {
      try {
        var entry = JSON.parse(lines[i]);
        var type = entry.type || "";
        if (type !== "user" && type !== "assistant") continue;

        var msg = entry.message || {};
        var msgContent = msg.content;
        var text = "";

        if (typeof msgContent === "string") {
          text = msgContent.slice(0, 250);
        } else if (Array.isArray(msgContent)) {
          var parts = [];
          for (var j = 0; j < msgContent.length; j++) {
            if (msgContent[j] && msgContent[j].type === "text" && msgContent[j].text) {
              parts.push(msgContent[j].text.slice(0, 200));
            }
          }
          text = parts.join(" ").slice(0, 250);
        }

        if (text) turns.push(type.toUpperCase() + ": " + text);
      } catch (e) {}
    }
    if (turns.length === 0) return "";
    return "RECENT CONVERSATION (" + turns.length + " turns):\n" + turns.join("\n");
  } catch (e) {
    return "";
  }
}

// ─── Exports ─────────────────────────────────────────────────────────────────

module.exports = {
  call: call,
  writeAnalysis: writeAnalysis,
  readTranscriptContext: readTranscriptContext,
  DEFAULT_CONFIG: DEFAULT_CONFIG
};

// ─── CLI mode ────────────────────────────────────────────────────────────────

if (require.main === module) {
  var args = process.argv.slice(2);
  var prompt = "";
  var jsonMode = false;

  for (var i = 0; i < args.length; i++) {
    if (args[i] === "--prompt" && args[i + 1]) { prompt = args[++i]; }
    else if (args[i] === "--json") { jsonMode = true; }
    else if (!args[i].startsWith("-")) { prompt = args[i]; }
  }

  if (!prompt) {
    try { prompt = fs.readFileSync(0, "utf-8").trim(); } catch (e) {}
  }

  if (!prompt) {
    process.stderr.write("Usage: echo 'prompt' | node haiku-client.js [--json]\n");
    process.stderr.write("       node haiku-client.js --prompt 'prompt' [--json]\n");
    process.stderr.write("\nEnvironment:\n");
    process.stderr.write("  HAIKU_ENDPOINT_URL  LLM endpoint (default: http://127.0.0.1:4100/v1/chat/completions)\n");
    process.stderr.write("  HAIKU_AUTH_TOKEN    Bearer token\n");
    process.stderr.write("  HAIKU_MODEL         Model ID (default: claude-4.5-haiku)\n");
    process.exit(1);
  }

  var result = call({ prompt: prompt, jsonMode: jsonMode, caller: "cli" });
  if (result.ok) {
    process.stdout.write(jsonMode && result.parsed ? JSON.stringify(result.parsed, null, 2) : result.content);
    process.stdout.write("\n");
  } else {
    process.stderr.write("ERROR: " + result.error + " (" + result.ms + "ms)\n");
    process.exit(1);
  }
}
