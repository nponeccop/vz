#!/usr/bin/env node
// vz-validate — validate v3 pod manifests against the subset vz honors.
//
// Usage: vz-validate <manifest.yaml> [<manifest.yaml> ...]
// Exits 0 if every manifest is valid, 1 otherwise. Reports all violations.

import { readFileSync } from "node:fs";
import { parseAllDocuments } from "yaml";
import { validateManifest, type Violation } from "./schema.ts";

export function validateFile(path: string): Violation[] {
  const errs: Violation[] = [];
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch (e) {
    return [{ path: "$", msg: `cannot read: ${(e as Error).message}` }];
  }

  const parsed = parseAllDocuments(text);
  // Surface YAML syntax errors before structural validation.
  for (const doc of parsed) {
    for (const err of doc.errors) {
      errs.push({ path: "$", msg: `cannot parse: ${err.message}` });
    }
  }
  if (errs.length) return errs;

  const docs = parsed.map((d) => d.toJS()).filter((d) => d !== null && d !== undefined);
  if (docs.length === 0) {
    errs.push({ path: "$", msg: "empty manifest (no YAML document)" });
  } else if (docs.length > 1) {
    errs.push({ path: "$", msg: "multiple documents in one file are not supported in v3 (one Pod per file)" });
  } else {
    validateManifest(docs[0], errs);
  }
  return errs;
}

function main(argv: string[]): number {
  const files = argv.slice(2);
  if (files.length === 0) {
    console.error("usage: vz-validate <manifest.yaml> [...]");
    return 2;
  }
  let bad = false;
  for (const path of files) {
    const errs = validateFile(path);
    if (errs.length) {
      bad = true;
      console.log(`FAIL ${path}`);
      for (const { path: p, msg } of errs) console.log(`  ${p}: ${msg}`);
    } else {
      console.log(`ok   ${path}`);
    }
  }
  return bad ? 1 : 0;
}

if (import.meta.main) {
  process.exit(main(process.argv));
}
