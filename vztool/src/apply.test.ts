import { test } from "node:test";
import assert from "node:assert/strict";
import { parse } from "yaml";
import { buildInventory } from "./apply.ts";
import type { HostTask } from "./plan.ts";

const tasks: HostTask[] = [
  {
    group: "lab",
    host: "10.0.0.1",
    user: "andy",
    podName: "antifraud",
    manifestPath: "/abs/pods/antifraud.yaml",
    containers: [
      { name: "gearmand", image: "localhost/gearmand-min:v3" },
      { name: "worker", image: "localhost/worker:v3" },
    ],
    images: ["localhost/gearmand-min:v3", "localhost/worker:v3"],
    ports: [{ port: 4730, protocol: "tcp" }],
  },
];

test("buildInventory emits a YAML inventory with each host's pod vars", () => {
  const inv = parse(buildInventory(tasks));
  const h = inv.all.hosts["10.0.0.1"];
  assert.equal(h.ansible_user, "andy");
  assert.equal(h.pod_name, "antifraud");
  assert.equal(h.pod_manifest, "/abs/pods/antifraud.yaml");
  assert.deepEqual(h.pod_images, ["localhost/gearmand-min:v3", "localhost/worker:v3"]);
  assert.deepEqual(h.pod_ports, [{ port: 4730, protocol: "tcp" }]);
});

test("buildInventory places every host under all.hosts", () => {
  const two: HostTask[] = [tasks[0], { ...tasks[0], host: "10.0.0.2" }];
  const inv = parse(buildInventory(two));
  assert.deepEqual(Object.keys(inv.all.hosts).sort(), ["10.0.0.1", "10.0.0.2"]);
});
