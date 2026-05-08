#!/usr/bin/env node
"use strict";
// Minimal event logger for hook-log.jsonl.
// Logs events only (fired/pass/block/ms) — no analysis text.
// Analysis text goes to each preprocessor's own instanceDir/analysis.log.

var fs = require("fs");
var path = require("path");

var LOG_PATH = path.join(process.env.HOME || "", ".claude", "hooks", "hook-log.jsonl");

function logEvent(event, moduleName, result, context) {
  var entry = {
    ts: new Date().toISOString(),
    event: event,
    module: moduleName,
    result: result
  };
  if (context) {
    if (context.ms !== undefined) entry.ms = context.ms;
    if (context.confidence) entry.confidence = context.confidence;
    if (context.tool) entry.tool = context.tool;
    if (context.project) entry.project = context.project;
    if (context.preview) entry.reason = context.preview.slice(0, 200);
  }
  try { fs.appendFileSync(LOG_PATH, JSON.stringify(entry) + "\n", "utf-8"); } catch (e) {}
}

function extractProject() {
  var cwd = process.cwd();
  var match = cwd.match(/([^/\\]+)$/);
  return match ? match[1] : "unknown";
}

module.exports = {
  logEvent: logEvent,
  extractProject: extractProject,
  LOG_PATH: LOG_PATH
};
