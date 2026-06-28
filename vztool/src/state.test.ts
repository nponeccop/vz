import { test } from "node:test";
import assert from "node:assert/strict";
import { parseActual, diffHost, type HostState } from "./state.ts";
import type { PodContainer } from "./plan.ts";

const PS_JSON = JSON.stringify([
  { Names: ["vzsmoke-alive"], Image: "localhost/vzsmoke:v3", State: "running", PodName: "vzsmoke", IsInfra: false },
  { Names: ["abc-infra"], Image: "localhost/podman-pause:v3", State: "running", PodName: "vzsmoke", IsInfra: true },
]);

const desired: PodContainer[] = [{ name: "alive", image: "localhost/vzsmoke:v3" }];

function reachable(pods: HostState["pods"]): HostState {
  return { host: "h", reachable: true, pods };
}

test("parseActual groups by pod and drops the infra container", () => {
  const pods = parseActual(PS_JSON);
  assert.equal(pods.length, 1);
  assert.equal(pods[0].podName, "vzsmoke");
  assert.equal(pods[0].containers.length, 1);
  assert.deepEqual(pods[0].containers[0], { name: "vzsmoke-alive", image: "localhost/vzsmoke:v3", state: "running" });
});

test("parseActual joins pod id -> name when podman leaves PodName empty", () => {
  const psJson = JSON.stringify([
    { Names: ["vzsmoke-alive"], Image: "localhost/vzsmoke:v3", State: "running", Pod: "abc123", PodName: "", IsInfra: false },
    { Names: ["abc-infra"], Image: "", State: "running", Pod: "abc123", PodName: "", IsInfra: true },
  ]);
  const podPsJson = JSON.stringify([{ Id: "abc123", Name: "vzsmoke" }]);
  const pods = parseActual(psJson, podPsJson);
  assert.equal(pods.length, 1);
  assert.equal(pods[0].podName, "vzsmoke");
  assert.equal(pods[0].containers[0].name, "vzsmoke-alive");
});

test("a converged host reports a single ok", () => {
  const state = reachable(parseActual(PS_JSON));
  const drifts = diffHost(state, "vzsmoke", desired);
  assert.deepEqual(drifts.map((d) => d.kind), ["ok"]);
});

test("a missing pod is pod-missing drift", () => {
  const drifts = diffHost(reachable([]), "vzsmoke", desired);
  assert.deepEqual(drifts.map((d) => d.kind), ["pod-missing"]);
});

test("an exited container is not-running drift", () => {
  const state = reachable([{ podName: "vzsmoke", containers: [{ name: "vzsmoke-alive", image: "localhost/vzsmoke:v3", state: "exited" }] }]);
  const drifts = diffHost(state, "vzsmoke", desired);
  assert.deepEqual(drifts.map((d) => d.kind), ["not-running"]);
});

test("a wrong image is image-mismatch drift", () => {
  const state = reachable([{ podName: "vzsmoke", containers: [{ name: "vzsmoke-alive", image: "localhost/vzsmoke:v2", state: "running" }] }]);
  const drifts = diffHost(state, "vzsmoke", desired);
  assert.ok(drifts.some((d) => d.kind === "image-mismatch"));
});

test("an unreachable host is its own drift, not a crash", () => {
  const state: HostState = { host: "h", reachable: false, pods: [], error: "timed out" };
  const drifts = diffHost(state, "vzsmoke", desired);
  assert.deepEqual(drifts.map((d) => d.kind), ["unreachable"]);
});

test("a pod not in desired is flagged unexpected", () => {
  const state = reachable([
    ...parseActual(PS_JSON),
    { podName: "stray", containers: [{ name: "stray-x", image: "localhost/x:v3", state: "running" }] },
  ]);
  const drifts = diffHost(state, "vzsmoke", desired);
  assert.ok(drifts.some((d) => d.kind === "unexpected-pod" && d.pod === "stray"));
});
