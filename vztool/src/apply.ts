#!/usr/bin/env node
// vz-apply — make the fleet's desired state actual.
//
// Thin wrapper over Ansible (the v3 executor). It validates the fleet, expands
// it into one task per host, generates a YAML inventory carrying each host's pod
// vars (name / manifest / images / ports), and invokes the `podman-pod` role:
//
//   ansible-playbook -i <generated-inventory> deploy.yaml
//
// The role does the idempotent work (guarded `podman image scp`, Quadlet unit,
// user systemd, firewalld) and reports real changed/ok — the deploy visibility
// the old hand-rolled ssh/scp path lacked. SSH is the only channel; nodes run no
// vz daemon.
//
// Usage: vz-apply <groups.yaml> [--user <name>] [--check]

import { execFileSync } from "node:child_process";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { stringify } from "yaml";
import { loadPlan, type HostTask } from "./plan.ts";

const here = dirname(fileURLToPath(import.meta.url));
// the unified Ansible home (ansible.cfg + roles/ + deploy.yaml live here)
const ANSIBLE_DIR = resolve(here, "../../ansible");

interface Opts {
  groupsPath: string;
  user: string;
  check: boolean;
}

function parseArgs(argv: string[]): Opts {
  let user = process.env.USER ?? "root";
  let check = false;
  const positional: string[] = [];
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--check" || a === "--dry-run") check = true;
    else if (a === "--user") user = argv[++i];
    else if (a.startsWith("--")) throw new Error(`unknown flag: ${a}`);
    else positional.push(a);
  }
  if (positional.length !== 1) throw new Error("usage: vz-apply <groups.yaml> [--user <name>] [--check]");
  return { groupsPath: positional[0], user, check };
}

// One YAML inventory for the whole fleet: each host carries the vars the
// podman-pod role consumes. Structured vars (image list, port dicts) are why
// this is a YAML inventory and not INI.
export function buildInventory(tasks: HostTask[]): string {
  const hosts: Record<string, unknown> = {};
  for (const t of tasks) {
    hosts[t.host] = {
      ansible_user: t.user,
      pod_name: t.podName,
      pod_manifest: t.manifestPath,
      pod_images: t.images,
      pod_ports: t.ports.map((p) => ({ port: p.port, protocol: p.protocol })),
    };
  }
  return stringify({ all: { hosts } });
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

  const invDir = mkdtempSync(join(tmpdir(), "vz-inv-"));
  const invPath = join(invDir, "inventory.yml");
  writeFileSync(invPath, buildInventory(tasks));

  const args = ["-i", invPath, "deploy.yaml"];
  if (opts.check) args.push("--check");
  console.log(`apply: ${tasks.length} host(s) via ansible-playbook${opts.check ? " [--check]" : ""}`);
  console.log(`  inventory: ${invPath}`);
  console.log(`  $ (cd ${ANSIBLE_DIR} && ansible-playbook ${args.join(" ")})\n`);

  try {
    execFileSync("ansible-playbook", args, { stdio: "inherit", cwd: ANSIBLE_DIR });
  } catch {
    console.error("\napply: ansible-playbook reported failures");
    return 1;
  }
  return 0;
}

if (import.meta.main) {
  process.exit(main(process.argv));
}
