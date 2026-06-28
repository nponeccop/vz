#!/usr/bin/env node
// vz-ps — fleet-wide actual state: what is really running on each host.
//
// Usage: vz-ps <groups.yaml> [--user <name>]

import { loadPlan } from "./plan.ts";
import { queryHost } from "./state.ts";

function parseArgs(argv: string[]): { groupsPath: string; user: string } {
  let user = process.env.USER ?? "root";
  const pos: string[] = [];
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--user") user = argv[++i];
    else pos.push(argv[i]);
  }
  if (pos.length !== 1) throw new Error("usage: vz-ps <groups.yaml> [--user <name>]");
  return { groupsPath: pos[0], user };
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

  const hosts = [...new Set(tasks.map((t) => t.host))];
  const pad = (s: string, n: number) => s.padEnd(n);
  console.log(`${pad("HOST", 16)}${pad("POD", 14)}${pad("CONTAINER", 22)}${pad("STATE", 10)}IMAGE`);
  for (const host of hosts) {
    const state = queryHost(opts.user, host);
    if (!state.reachable) {
      console.log(`${pad(host, 16)}${pad("-", 14)}${pad("UNREACHABLE", 22)}${pad("-", 10)}${state.error ?? ""}`);
      continue;
    }
    if (state.pods.length === 0) {
      console.log(`${pad(host, 16)}${pad("(none)", 14)}`);
      continue;
    }
    for (const pod of state.pods) {
      for (const c of pod.containers) {
        console.log(`${pad(host, 16)}${pad(pod.podName || "-", 14)}${pad(c.name, 22)}${pad(c.state, 10)}${c.image}`);
      }
    }
  }
  return 0;
}

if (import.meta.main) {
  process.exit(main(process.argv));
}
