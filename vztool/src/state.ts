// Fleet actual-state: query what is really running on each host (podman ps over
// SSH) and diff it against the desired pods. The diff is the product surface —
// what tells you a node rebooted and came back empty, or a deploy half-applied.

import { execFileSync } from "node:child_process";
import type { PodContainer } from "./plan.ts";

const SSH_OPTS = ["-o", "StrictHostKeyChecking=accept-new"];

export interface ActualContainer {
  name: string;
  image: string;
  state: string; // running | exited | created | ...
}
export interface ActualPod {
  podName: string;
  containers: ActualContainer[];
}
export interface HostState {
  host: string;
  reachable: boolean;
  pods: ActualPod[];
  error?: string;
}

const MARKER = "@@@VZ@@@";

// Parse `podman ps -a --format json` into pods, dropping infra containers.
// `podman ps` leaves PodName empty in some builds (only the Pod id is set), so
// the optional `podPsJson` (`podman pod ps --format json`) supplies id -> name.
export function parseActual(psJson: string, podPsJson?: string): ActualPod[] {
  const idToName = new Map<string, string>();
  if (podPsJson) {
    for (const p of JSON.parse(podPsJson) as any[]) idToName.set(p.Id, p.Name);
  }
  const arr = JSON.parse(psJson) as any[];
  const byPod = new Map<string, ActualContainer[]>();
  for (const c of arr) {
    if (c.IsInfra) continue;
    const podName: string = idToName.get(c.Pod) ?? c.PodName ?? "";
    const name: string = Array.isArray(c.Names) ? c.Names[0] : (c.Names ?? "");
    if (!byPod.has(podName)) byPod.set(podName, []);
    byPod.get(podName)!.push({ name, image: c.Image ?? "", state: c.State ?? "" });
  }
  return [...byPod].map(([podName, containers]) => ({ podName, containers }));
}

// Query one host's actual state. Unreachable is a state, not a crash.
export function queryHost(user: string, host: string): HostState {
  const cmd = `podman pod ps --format json; echo '${MARKER}'; podman ps -a --format json`;
  try {
    const out = execFileSync("ssh", [...SSH_OPTS, `${user}@${host}`, cmd], { encoding: "utf8" });
    const [podPsJson, psJson] = out.split(MARKER);
    return { host, reachable: true, pods: parseActual(psJson, podPsJson) };
  } catch (e) {
    return { host, reachable: false, pods: [], error: (e as Error).message.split("\n")[0] };
  }
}

export type DriftKind =
  | "ok"
  | "unreachable"
  | "pod-missing"
  | "container-missing"
  | "not-running"
  | "image-mismatch"
  | "unexpected-pod";

export interface Drift {
  host: string;
  pod: string;
  container?: string;
  kind: DriftKind;
  detail?: string;
}

// Compare one host's desired pod against its actual state. Container names from
// `podman kube play` are "<podName>-<containerName>".
export function diffHost(
  state: HostState,
  desiredPodName: string,
  desiredContainers: PodContainer[],
): Drift[] {
  if (!state.reachable) {
    return [{ host: state.host, pod: desiredPodName, kind: "unreachable", detail: state.error }];
  }

  const drifts: Drift[] = [];
  const actual = state.pods.find((p) => p.podName === desiredPodName);
  if (!actual) {
    drifts.push({ host: state.host, pod: desiredPodName, kind: "pod-missing" });
  } else {
    for (const dc of desiredContainers) {
      const cname = `${desiredPodName}-${dc.name}`;
      const ac = actual.containers.find((c) => c.name === cname);
      if (!ac) {
        drifts.push({ host: state.host, pod: desiredPodName, container: cname, kind: "container-missing" });
        continue;
      }
      if (ac.image !== dc.image) {
        drifts.push({
          host: state.host,
          pod: desiredPodName,
          container: cname,
          kind: "image-mismatch",
          detail: `desired ${dc.image}, actual ${ac.image}`,
        });
      }
      if (ac.state !== "running") {
        drifts.push({ host: state.host, pod: desiredPodName, container: cname, kind: "not-running", detail: ac.state });
      }
    }
  }

  // Pods running on the host that the desired state does not mention.
  for (const p of state.pods) {
    if (p.podName && p.podName !== desiredPodName) {
      drifts.push({ host: state.host, pod: p.podName, kind: "unexpected-pod" });
    }
  }

  if (drifts.length === 0) drifts.push({ host: state.host, pod: desiredPodName, kind: "ok" });
  return drifts;
}
