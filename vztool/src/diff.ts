#!/usr/bin/env node
// vz-diff — desired (git) minus actual (podman ps). The product surface: it
// tells you a node came back empty after a reboot, or a deploy half-applied.
//
// Usage: vz-diff <groups.yaml> [--user <name>]
// Exits 0 if the fleet matches desired, 1 if any drift, 2 on bad usage.

import { loadPlan } from "./plan.ts";
import { queryHost, diffHost, type Drift } from "./state.ts";

function parseArgs(argv: string[]): { groupsPath: string; user: string } {
  let user = process.env.USER ?? "root";
  const pos: string[] = [];
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--user") user = argv[++i];
    else pos.push(argv[i]);
  }
  if (pos.length !== 1) throw new Error("usage: vz-diff <groups.yaml> [--user <name>]");
  return { groupsPath: pos[0], user };
}

function line(d: Drift): string {
  const where = d.container ? `${d.pod}/${d.container}` : d.pod;
  const detail = d.detail ? ` (${d.detail})` : "";
  return `${d.host}  ${d.kind}  ${where}${detail}`;
}

function main(argv: string[]): number {
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (e) {
    console.error((e as Error).message);
    return 2;
  }

  let tasks;
  try {
    tasks = loadPlan(opts.groupsPath, opts.user);
  } catch (e) {
    console.error((e as Error).message);
    return 1;
  }

  let drifted = 0;
  for (const t of tasks) {
    const state = queryHost(opts.user, t.host);
    for (const d of diffHost(state, t.podName, t.containers)) {
      if (d.kind === "ok") {
        console.log(`ok    ${line(d)}`);
      } else {
        drifted++;
        console.log(`DRIFT ${line(d)}`);
      }
    }
  }

  if (drifted) {
    console.log(`\ndiff: ${drifted} drift(s)`);
    return 1;
  }
  console.log(`\ndiff: fleet matches desired`);
  return 0;
}

if (import.meta.main) {
  process.exit(main(process.argv));
}
