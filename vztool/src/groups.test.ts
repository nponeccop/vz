import { test } from "node:test";
import assert from "node:assert/strict";
import { validateGroups, type GroupRef } from "./groups.ts";
import type { Violation } from "./schema.ts";

function check(doc: unknown): { paths: string[]; refs: GroupRef[] } {
  const errs: Violation[] = [];
  const refs = validateGroups(doc, errs);
  return { paths: errs.map((e) => e.path), refs };
}

const good = {
  groups: {
    "node-a": { hosts: ["10.10.10.67", "10.10.10.68"], pod: "pods/antifraud.yaml" },
    edge: { hosts: ["203.0.113.5"], pod: "pods/edge.yaml" },
  },
};

test("a valid topology passes and returns one ref per group", () => {
  const { paths, refs } = check(good);
  assert.deepEqual(paths, []);
  assert.equal(refs.length, 2);
  assert.deepEqual(refs[0], { name: "node-a", hosts: ["10.10.10.67", "10.10.10.68"], pod: "pods/antifraud.yaml" });
});

test("unsupported top-level and per-group fields are rejected", () => {
  const { paths } = check({ ...good, version: 1, groups: { g: { hosts: ["x"], pod: "p", extra: 1 } } });
  assert.ok(paths.includes("$.version"));
  assert.ok(paths.includes("$.groups.g.extra"));
});

test("a group needs a non-empty hosts list and a pod", () => {
  const { paths } = check({ groups: { g: { hosts: [], pod: "" } } });
  assert.ok(paths.includes("$.groups.g.hosts"));
  assert.ok(paths.includes("$.groups.g.pod"));
});

test("a host in two groups is rejected (one pod per host)", () => {
  const { paths } = check({
    groups: {
      a: { hosts: ["10.0.0.1"], pod: "a.yaml" },
      b: { hosts: ["10.0.0.1"], pod: "b.yaml" },
    },
  });
  assert.ok(paths.some((p) => p.startsWith("$.groups.b.hosts")));
});

test("a duplicate host within a group is flagged", () => {
  const { paths } = check({ groups: { a: { hosts: ["10.0.0.1", "10.0.0.1"], pod: "a.yaml" } } });
  assert.ok(paths.includes("$.groups.a.hosts[1]"));
});

test("empty groups mapping is rejected", () => {
  const { paths } = check({ groups: {} });
  assert.ok(paths.includes("$.groups"));
});
