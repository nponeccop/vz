import { test } from "node:test";
import assert from "node:assert/strict";
import { kubeUnit, serviceName } from "./unit.ts";

test("kubeUnit references the pod manifest and installs to default.target", () => {
  const u = kubeUnit("antifraud");
  assert.match(u, /\[Kube\]/);
  assert.match(u, /^Yaml=antifraud\.yaml$/m);
  assert.match(u, /^WantedBy=default\.target$/m);
});

test("serviceName maps <pod> to <pod>.service", () => {
  assert.equal(serviceName("antifraud"), "antifraud.service");
});
