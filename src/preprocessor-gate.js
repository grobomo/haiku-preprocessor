#!/usr/bin/env node
"use strict";
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ PREPROCESSOR GATE — Haiku triage for user prompts                       │
// │                                                                         │
// │ Analyzes user prompts via Haiku, writes analysis to instance directory. │
// │ Returns pass/block decision for the hook runner to act on.              │
// │                                                                         │
// │ Instance directory (e.g. ~/.claude/hooks/preprocessors/user-prompt/):   │
// │   analysis.md   — latest analysis (consumer reads this)                 │
// │   analysis.log  — appending timestamped history (for audit/review)      │
// │                                                                         │
// │ Hook-log gets events only (fired/pass/block/ms/confidence).             │
// │                                                                         │
// │ Config: rules YAML file (path passed by caller or env)                  │
// │ Bypass: messages starting with "!" skip analysis entirely.              │
// │ Safety: Haiku timeout/failure → always pass through (never block)       │
// └─────────────────────────────────────────────────────────────────────────┘

var fs = require("fs");
var path = require("path");
var haiku = require("./haiku-client");

var BLOCK_COUNTER_FILE = ".block-count";
var MAX_CONSECUTIVE_BLOCKS = 3;

// preprocess(options)
//
// Options:
//   prompt          — string (required): user's message
//   transcriptPath  — string (optional): path to session transcript JSONL
//   sessionId       — string (optional): session ID for scoping
//   instanceDir     — string (required): where to write analysis.md / analysis.log
//   rulesPath       — string (required): path to rules YAML file
//
// Returns: {
//   action: "pass"|"block",
//   text?:   string,  — injected context for the LLM (action=pass only)
//   reason?: string,  — shown to user (action=block only)
//   bypass?: boolean, — true if "!" prefix was used
// }

function preprocess(options) {
  var prompt = options.prompt || "";
  var instanceDir = options.instanceDir || "";
  var rulesPath = options.rulesPath || "";

  // Bypass: "!" prefix
  if (prompt.trimStart().startsWith("!")) {
    return { action: "pass", bypass: true };
  }

  // Read rules
  var rules;
  try {
    rules = fs.readFileSync(rulesPath, "utf-8");
  } catch (e) {
    return { action: "pass" };
  }

  // Gather conversation context
  var recentContext = haiku.readTranscriptContext(options.transcriptPath, 10);

  // Build Haiku prompt
  var haikuPrompt = [
    "You are L1 — a fast triage layer that interprets user prompts before they reach the main assistant.",
    "Your job: resolve shorthand, detect ambiguity, and write analysis notes.",
    "You have conversation context below — use it to understand what the user is referring to.",
    "",
    "RULES AND SHORTHAND:",
    rules,
    recentContext ? "\n" + recentContext + "\n" : "",
    "CURRENT USER PROMPT:",
    prompt,
    "",
    "Analyze the prompt against the rules and conversation context. Return EXACTLY this JSON (no other text):",
    '{',
    '  "confidence": "high|medium|low",',
    '  "notes": "Your full analysis — what the user means, resolved paths, suggested approach",',
    '  "shorthand_resolved": "The prompt rewritten with shorthand expanded (or null if none found)",',
    '  "question": "If low confidence: the clarification question to ask. Otherwise null"',
    '}',
    "",
    "Confidence guide:",
    "- high: You know what they mean (including from conversation context). Clear intent.",
    "- medium: 60-80% sure. Ambiguous task request with multiple possible actions.",
    "- low: Genuinely can't determine what action they want. No matching context or rules.",
    "",
    "IMPORTANT: Conversational responses (confirmations, reactions, feedback, follow-ups",
    "to the ongoing discussion) are ALWAYS high confidence. Only flag medium/low for",
    "actual task requests where the specific action or target is unclear.",
  ].join("\n");

  // Call Haiku
  var result = haiku.call({
    prompt: haikuPrompt,
    jsonMode: true,
    caller: "preprocessor-gate",
    maxTokens: 500
  });

  if (!result.ok) {
    return { action: "pass" };
  }

  var parsed = result.parsed;
  var confidence = (parsed.confidence || "high").toLowerCase();
  var notes = parsed.notes || "";
  var shorthandResolved = parsed.shorthand_resolved || null;
  var question = parsed.question || null;

  // Write analysis to instance directory
  var shortId = (options.sessionId || "default").slice(0, 8);
  var analysisContent = [
    "# L1 Analysis",
    "",
    "**Session:** " + shortId,
    "**Timestamp:** " + new Date().toISOString(),
    "**Confidence:** " + confidence,
    "**Original prompt:** " + prompt,
    shorthandResolved ? "**Resolved:** " + shorthandResolved : null,
    "",
    "## Notes",
    "",
    notes,
    question ? "\n## Clarification Needed\n\n" + question : null,
  ].filter(Boolean).join("\n");

  haiku.writeAnalysis(instanceDir, analysisContent);

  // Decision
  if (confidence === "low") {
    var blockCount = readBlockCount(instanceDir);
    if (blockCount >= MAX_CONSECUTIVE_BLOCKS) {
      writeBlockCount(instanceDir, 0);
      return { action: "pass", text: analysisPointer(instanceDir) + " (passed through after " + MAX_CONSECUTIVE_BLOCKS + " consecutive blocks)" };
    }
    writeBlockCount(instanceDir, blockCount + 1);
    return { action: "block", reason: "L1: " + (question || "Could you clarify what you need?") };
  }

  writeBlockCount(instanceDir, 0);
  var text = analysisPointer(instanceDir);
  if (confidence === "medium") {
    text += " L1 flagged some ambiguity — ask user to confirm before acting on uncertain parts.";
  }
  return { action: "pass", text: text, confidence: confidence, ms: result.ms };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function analysisPointer(instanceDir) {
  return "L1 analysis available at " + path.join(instanceDir, "analysis.md") + " — read it before proceeding.";
}

function readBlockCount(instanceDir) {
  try {
    return parseInt(fs.readFileSync(path.join(instanceDir, BLOCK_COUNTER_FILE), "utf-8").trim(), 10) || 0;
  } catch (e) { return 0; }
}

function writeBlockCount(instanceDir, n) {
  try {
    fs.mkdirSync(instanceDir, { recursive: true });
    fs.writeFileSync(path.join(instanceDir, BLOCK_COUNTER_FILE), String(n), "utf-8");
  } catch (e) {}
}

// ─── Exports ─────────────────────────────────────────────────────────────────

module.exports = { preprocess: preprocess };
