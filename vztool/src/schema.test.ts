import { test } from "node:test";
import assert from "node:assert/strict";
import { validateManifest, type Violation } from "./schema.ts";

function check(doc: unknown): string[] {
  const errs: Violation[] = [];
  validateManifest(doc, errs);
  return errs.map((e) => e.path);
}

const goodPod = {
  apiVersion: "v1",
  kind: "Pod",
  metadata: { name: "antifraud" },
  spec: {
    hostNetwork: true,
    containers: [
      { name: "gearmand", image: "localhost/gearmand:v3", imagePullPolicy: "Never", ports: [{ containerPort: 4730 }] },
      {
        name: "dns-resolver",
        image: "localhost/dns-resolver:v3",
        imagePullPolicy: "Never",
        command: ["node", "index.js"],
        env: [{ name: "LOG", value: "info" }],
      },
    ],
  },
};

test("a valid host-network pod passes clean", () => {
  assert.deepEqual(check(goodPod), []);
});

test("unsupported top-level and spec fields are rejected by path", () => {
  const paths = check({ ...goodPod, status: {}, spec: { ...goodPod.spec, volumes: [] } });
  assert.ok(paths.includes("$.status"));
  assert.ok(paths.includes("$.spec.volumes"));
});

test("a registry image (not localhost/) is rejected", () => {
  const paths = check({
    ...goodPod,
    spec: { containers: [{ name: "x", image: "docker.io/library/busybox", imagePullPolicy: "Never" }] },
  });
  assert.ok(paths.includes("$.spec.containers[0].image"));
});

test("imagePullPolicy must be Never", () => {
  const paths = check({
    ...goodPod,
    spec: { containers: [{ name: "x", image: "localhost/x:v3", imagePullPolicy: "Always" }] },
  });
  assert.ok(paths.includes("$.spec.containers[0].imagePullPolicy"));
});

test("wrong apiVersion and kind are flagged", () => {
  const paths = check({ ...goodPod, apiVersion: "apps/v1", kind: "Deployment" });
  assert.ok(paths.includes("$.apiVersion"));
  assert.ok(paths.includes("$.kind"));
});

test("empty container list is rejected", () => {
  const paths = check({ ...goodPod, spec: { containers: [] } });
  assert.ok(paths.includes("$.spec.containers"));
});

test("duplicate container names are flagged", () => {
  const paths = check({
    ...goodPod,
    spec: {
      containers: [
        { name: "dup", image: "localhost/a:v3", imagePullPolicy: "Never" },
        { name: "dup", image: "localhost/b:v3", imagePullPolicy: "Never" },
      ],
    },
  });
  assert.ok(paths.includes("$.spec.containers[1].name"));
});

test("a bad port and an unknown port field are rejected", () => {
  const paths = check({
    ...goodPod,
    spec: { containers: [{ name: "x", image: "localhost/x:v3", imagePullPolicy: "Never", ports: [{ containerPort: 99999, hostPort: 8080 }] }] },
  });
  assert.ok(paths.includes("$.spec.containers[0].ports[0].containerPort"));
  assert.ok(paths.includes("$.spec.containers[0].ports[0].hostPort"));
});

test("an unknown env key is rejected", () => {
  const paths = check({
    ...goodPod,
    spec: {
      containers: [
        { name: "x", image: "localhost/x:v3", imagePullPolicy: "Never", env: [{ name: "A", valueFrom: {} }] },
      ],
    },
  });
  assert.ok(paths.includes("$.spec.containers[0].env[0].valueFrom"));
});
