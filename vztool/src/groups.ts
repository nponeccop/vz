// Validation of the fleet topology file (groups.yaml): which hosts run which
// pod. This is vz's own format, not Kubernetes — placement, not workload.
// Pure (no IO); the caller resolves and validates the referenced pod files.

import type { Violation } from "./schema.ts";

const TOP_KEYS = ["groups"];
const GROUP_KEYS = ["hosts", "pod"];

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === "object" && x !== null && !Array.isArray(x);
}

// A structurally-valid group, surfaced so the caller can validate the pod file.
export interface GroupRef {
  name: string;
  hosts: string[];
  pod: string;
}

// Validate groups.yaml structure. Appends violations and returns the
// well-formed group references (so the caller can go validate each pod).
export function validateGroups(doc: unknown, errs: Violation[]): GroupRef[] {
  if (!isRecord(doc)) {
    errs.push({ path: "$", msg: `expected a mapping, got ${doc === null ? "null" : typeof doc}` });
    return [];
  }
  for (const k of Object.keys(doc)) {
    if (!TOP_KEYS.includes(k)) {
      errs.push({ path: `$.${k}`, msg: `unsupported field (vz honors only: ${TOP_KEYS.join(", ")})` });
    }
  }

  const groups = doc.groups;
  if (!isRecord(groups) || Object.keys(groups).length === 0) {
    errs.push({ path: "$.groups", msg: "required, must be a non-empty mapping of group name -> { hosts, pod }" });
    return [];
  }

  const refs: GroupRef[] = [];
  const hostToGroup = new Map<string, string>();

  for (const [name, g] of Object.entries(groups)) {
    const gp = `$.groups.${name}`;
    if (!isRecord(g)) {
      errs.push({ path: gp, msg: "must be a mapping with { hosts, pod }" });
      continue;
    }
    for (const k of Object.keys(g)) {
      if (!GROUP_KEYS.includes(k)) {
        errs.push({ path: `${gp}.${k}`, msg: `unsupported field (vz honors only: ${GROUP_KEYS.join(", ")})` });
      }
    }

    let okHosts = true;
    const hosts = g.hosts;
    if (!Array.isArray(hosts) || hosts.length === 0) {
      errs.push({ path: `${gp}.hosts`, msg: "required, must be a non-empty list of host/IP strings" });
      okHosts = false;
    } else {
      const seenInGroup = new Set<string>();
      hosts.forEach((h, i) => {
        if (typeof h !== "string" || h === "") {
          errs.push({ path: `${gp}.hosts[${i}]`, msg: "must be a non-empty string" });
          okHosts = false;
          return;
        }
        if (seenInGroup.has(h)) {
          errs.push({ path: `${gp}.hosts[${i}]`, msg: `duplicate host ${JSON.stringify(h)} within group` });
        }
        seenInGroup.add(h);
        const prev = hostToGroup.get(h);
        if (prev && prev !== name) {
          errs.push({ path: `${gp}.hosts[${i}]`, msg: `host ${JSON.stringify(h)} is already in group ${JSON.stringify(prev)} — a host runs one pod` });
        }
        hostToGroup.set(h, name);
      });
    }

    const pod = g.pod;
    let okPod = true;
    if (typeof pod !== "string" || pod === "") {
      errs.push({ path: `${gp}.pod`, msg: "required, must be a path to a pod manifest" });
      okPod = false;
    }

    if (okHosts && okPod) {
      refs.push({ name, hosts: hosts as string[], pod: pod as string });
    }
  }
  return refs;
}
