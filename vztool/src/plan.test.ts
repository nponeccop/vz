import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { loadPlan } from "./plan.ts";

const here = dirname(fileURLToPath(import.meta.url));
const exampleGroups = resolve(here, "../../fleet.example/groups.yaml");

test("loadPlan expands a group into one task per host with the pod's images", () => {
  const tasks = loadPlan(exampleGroups, "andy");
  // node-a has two hosts -> two tasks
  assert.equal(tasks.length, 2);
  for (const t of tasks) {
    assert.equal(t.group, "node-a");
    assert.equal(t.user, "andy");
    assert.equal(t.podName, "antifraud");
    assert.deepEqual(t.images, ["localhost/gearmand:v3", "localhost/dns-resolver:v3"]);
  }
  assert.deepEqual(tasks.map((t) => t.host).sort(), ["10.10.10.67", "10.10.10.68"]);
});

test("loadPlan refuses to apply an invalid fleet", () => {
  const bad = resolve(here, "fixtures-does-not-exist.yaml");
  assert.throws(() => loadPlan(bad, "andy"), /refusing to apply/);
});
