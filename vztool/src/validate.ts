#!/usr/bin/env node
// vz-validate — validate v3 desired state against the subset vz honors.
//
// Pass a fleet topology file (groups.yaml) to validate the whole fleet (the
// topology plus every pod it references), or pass pod manifests directly.
//
// Usage: vz-validate <groups.yaml | pod.yaml> [...]
// Exits 0 if everything is valid, 1 otherwise. Reports all violations.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseAllDocuments } from "yaml";
import { validateManifest, type Violation } from "./schema.ts";
import { validateGroups } from "./groups.ts";

export interface FileResult {
  path: string;
  errs: Violation[];
}

// Parse exactly one YAML document from `text`; push violations for syntax
// errors, emptiness, or multi-document files. Returns undefined on failure.
function parseSingle(text: string, errs: Violation[]): unknown {
  const parsed = parseAllDocuments(text);
  for (const doc of parsed) {
    for (const err of doc.errors) errs.push({ path: "$", msg: `cannot parse: ${err.message}` });
  }
  if (errs.length) return undefined;
  const docs = parsed.map((d) => d.toJS()).filter((d) => d !== null && d !== undefined);
  if (docs.length === 0) {
    errs.push({ path: "$", msg: "empty file (no YAML document)" });
  } else if (docs.length > 1) {
    errs.push({ path: "$", msg: "multiple documents in one file are not supported in v3 (one per file)" });
  } else {
    return docs[0];
  }
  return undefined;
}

function readAndParse(path: string): { doc: unknown; errs: Violation[] } {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch (e) {
    return { doc: undefined, errs: [{ path: "$", msg: `cannot read: ${(e as Error).message}` }] };
  }
  const errs: Violation[] = [];
  return { doc: parseSingle(text, errs), errs };
}

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === "object" && x !== null && !Array.isArray(x);
}

// Validate one path. A file with a top-level `groups` key is a fleet topology:
// it is validated, then each pod it references is validated too. Returns one
// FileResult per file touched (the topology plus referenced pods).
export function validate(path: string): FileResult[] {
  const { doc, errs } = readAndParse(path);
  if (doc === undefined) return [{ path, errs }];

  if (isRecord(doc) && "groups" in doc) {
    const refs = validateGroups(doc, errs);
    const results: FileResult[] = [{ path, errs }];
    const base = dirname(path);
    const seen = new Set<string>();
    for (const ref of refs) {
      const podPath = resolve(base, ref.pod);
      if (seen.has(podPath)) continue;
      seen.add(podPath);
      const podErrs: Violation[] = [];
      const { doc: podDoc, errs: readErrs } = readAndParse(podPath);
      podErrs.push(...readErrs);
      if (podDoc !== undefined) validateManifest(podDoc, podErrs);
      results.push({ path: ref.pod, errs: podErrs });
    }
    return results;
  }

  // A bare pod manifest.
  validateManifest(doc, errs);
  return [{ path, errs }];
}

function main(argv: string[]): number {
  const files = argv.slice(2);
  if (files.length === 0) {
    console.error("usage: vz-validate <groups.yaml | pod.yaml> [...]");
    return 2;
  }
  let bad = false;
  for (const path of files) {
    for (const { path: p, errs } of validate(path)) {
      if (errs.length) {
        bad = true;
        console.log(`FAIL ${p}`);
        for (const { path: vp, msg } of errs) console.log(`  ${vp}: ${msg}`);
      } else {
        console.log(`ok   ${p}`);
      }
    }
  }
  return bad ? 1 : 0;
}

if (import.meta.main) {
  process.exit(main(process.argv));
}
