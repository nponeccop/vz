#!/usr/bin/env node
// vz-apply — make the fleet's desired state actual.
//
// For each host in each group: push the pod's images with `podman image scp`
// (whole-image transfer over SSH — see SPEC-v3.md), copy the manifest, and run
// `podman kube play --replace` so the running pod matches the manifest.
//
// Usage: vz-apply <groups.yaml> [--user <name>] [--dry-run]
//
// Reboot survival (Quadlet) is step 5; this command starts the pod now.

import { execFileSync } from "node:child_process";
import { loadPlan, type HostTask } from "./plan.ts";

const SSH_OPTS = ["-o", "StrictHostKeyChecking=accept-new"];
const REMOTE_DIR = ".config/vz"; // relative to the remote user's home

interface Opts {
  groupsPath: string;
  user: string;
  dryRun: boolean;
}

function parseArgs(argv: string[]): Opts {
  let user = process.env.USER ?? "root";
  let dryRun = false;
  const positional: string[] = [];
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") dryRun = true;
    else if (a === "--user") user = argv[++i];
    else if (a.startsWith("--")) throw new Error(`unknown flag: ${a}`);
    else positional.push(a);
  }
  if (positional.length !== 1) throw new Error("usage: vz-apply <groups.yaml> [--user <name>] [--dry-run]");
  return { groupsPath: positional[0], user, dryRun };
}

function run(cmd: string, args: string[], dryRun: boolean): void {
  console.log(`  $ ${cmd} ${args.join(" ")}`);
  if (!dryRun) execFileSync(cmd, args, { stdio: "inherit" });
}

function applyHost(t: HostTask, dryRun: boolean): void {
  const target = `${t.user}@${t.host}`;
  console.log(`\n# ${t.group} -> ${target}  (pod ${t.podName})`);

  for (const image of t.images) {
    // trailing :: keeps the same image name on the remote
    run("podman", ["image", "scp", image, `${target}::`], dryRun);
  }

  const remoteFile = `${REMOTE_DIR}/${t.podName}.yaml`;
  run("ssh", [...SSH_OPTS, target, "mkdir", "-p", REMOTE_DIR], dryRun);
  run("scp", [...SSH_OPTS, t.manifestPath, `${target}:${remoteFile}`], dryRun);
  run("ssh", [...SSH_OPTS, target, "podman", "kube", "play", "--replace", remoteFile], dryRun);
}

function main(argv: string[]): number {
  let opts: Opts;
  try {
    opts = parseArgs(argv);
  } catch (e) {
    console.error((e as Error).message);
    return 2;
  }

  let tasks: HostTask[];
  try {
    tasks = loadPlan(opts.groupsPath, opts.user);
  } catch (e) {
    console.error((e as Error).message);
    return 1;
  }

  console.log(`apply: ${tasks.length} host(s)${opts.dryRun ? " [dry-run]" : ""}`);
  let failed = 0;
  for (const t of tasks) {
    try {
      applyHost(t, opts.dryRun);
    } catch (e) {
      failed++;
      console.error(`  ! ${t.user}@${t.host}: ${(e as Error).message}`);
    }
  }
  if (failed) {
    console.error(`\napply: ${failed}/${tasks.length} host(s) failed`);
    return 1;
  }
  console.log(`\napply: ok (${tasks.length} host(s))`);
  return 0;
}

if (import.meta.main) {
  process.exit(main(process.argv));
}
