// Build an apply plan from a fleet topology file: validate it, then expand
// every group into one task per host, carrying the pod name, manifest path,
// and the images that host needs.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseAllDocuments } from "yaml";
import { validate } from "./validate.ts";
import { validateGroups } from "./groups.ts";

export interface HostTask {
  group: string;
  host: string;
  user: string;
  podName: string;
  manifestPath: string; // absolute path to the pod manifest
  images: string[]; // unique images referenced by the pod
}

function readSingle(path: string): Record<string, any> {
  const docs = parseAllDocuments(readFileSync(path, "utf8"))
    .map((d) => d.toJS())
    .filter((d) => d !== null && d !== undefined);
  return docs[0] as Record<string, any>;
}

// Validate the fleet and return the per-host apply tasks. Throws with a
// human-readable report if the fleet is invalid (apply must never run on a
// fleet that would not pass validation).
export function loadPlan(groupsPath: string, user: string): HostTask[] {
  const results = validate(groupsPath);
  const bad = results.filter((r) => r.errs.length);
  if (bad.length) {
    const lines = bad.flatMap((r) => [`FAIL ${r.path}`, ...r.errs.map((e) => `  ${e.path}: ${e.msg}`)]);
    throw new Error("refusing to apply — fleet is invalid:\n" + lines.join("\n"));
  }

  const base = dirname(groupsPath);
  const refs = validateGroups(readSingle(groupsPath), []); // already known valid

  const podCache = new Map<string, { name: string; images: string[] }>();
  const tasks: HostTask[] = [];
  for (const ref of refs) {
    const manifestPath = resolve(base, ref.pod);
    let pod = podCache.get(manifestPath);
    if (!pod) {
      const doc = readSingle(manifestPath);
      const images: string[] = doc.spec.containers.map((c: any) => c.image);
      pod = { name: doc.metadata.name, images: [...new Set(images)] };
      podCache.set(manifestPath, pod);
    }
    for (const host of ref.hosts) {
      tasks.push({ group: ref.name, host, user, podName: pod.name, manifestPath, images: pod.images });
    }
  }
  return tasks;
}
