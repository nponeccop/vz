#!/usr/bin/env node
// vz-apply — make the fleet's desired state actual.
//
// For each host in each group: push the pod's images with `podman image scp`
// (whole-image transfer over SSH — see SPEC-v3.md), then install the manifest
// as a rootless Quadlet `.kube` unit and (re)start it via the user systemd
// manager. systemd owns the pod, so it also comes back on reboot.
//
// Usage: vz-apply <groups.yaml> [--user <name>] [--dry-run]

import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadPlan, type HostTask } from "./plan.ts";
import { kubeUnit, serviceName } from "./unit.ts";

const SSH_OPTS = ["-o", "StrictHostKeyChecking=accept-new"];
// rootless Quadlet dir, relative to the remote user's home
const REMOTE_DIR = ".config/containers/systemd";

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

  const remoteYaml = `${REMOTE_DIR}/${t.podName}.yaml`;
  const remoteKube = `${REMOTE_DIR}/${t.podName}.kube`;
  run("ssh", [...SSH_OPTS, target, "mkdir", "-p", REMOTE_DIR], dryRun);
  run("scp", [...SSH_OPTS, t.manifestPath, `${target}:${remoteYaml}`], dryRun);

  // install the Quadlet .kube unit beside the manifest
  const kubePath = join(tmpdir(), `vz-${t.podName}.kube`);
  if (!dryRun) writeFileSync(kubePath, kubeUnit(t.podName));
  run("scp", [...SSH_OPTS, kubePath, `${target}:${remoteKube}`], dryRun);

  // regenerate units and (re)start via the user manager; XDG_RUNTIME_DIR is set
  // because `systemctl --user` over a non-login SSH session has no bus otherwise
  const svc = serviceName(t.podName);
  const remoteCmd = `export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user daemon-reload && systemctl --user restart ${svc}`;
  run("ssh", [...SSH_OPTS, target, remoteCmd], dryRun);
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
