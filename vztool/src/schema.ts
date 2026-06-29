// Validation of a v3 pod manifest against the subset vz actually honors.
//
// Intentionally STRICTER than `podman kube play`. podman silently ignores many
// PodSpec fields; vz refuses them. A field that looks supported but is a no-op
// is a deploy-time landmine, so every field outside the whitelist is a hard
// error. See SPEC-v3.md ("Kubernetes YAML — a real, validated subset").

export interface Violation {
  path: string;
  msg: string;
}

// Allowed keys at each level. Anything not listed is rejected loudly.
const POD_KEYS = ["apiVersion", "kind", "metadata", "spec"];
const METADATA_KEYS = ["name", "labels"];
const SPEC_KEYS = ["hostNetwork", "restartPolicy", "containers"];
const CONTAINER_KEYS = ["name", "image", "imagePullPolicy", "command", "args", "env", "ports"];
const ENV_KEYS = ["name", "value"];
const PORT_KEYS = ["containerPort", "protocol"];
const RESTART_POLICIES = ["Always", "OnFailure", "Never"];
const PROTOCOLS = ["TCP", "UDP"];

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === "object" && x !== null && !Array.isArray(x);
}

function isStringList(x: unknown): x is string[] {
  return Array.isArray(x) && x.every((e) => typeof e === "string");
}

// Reject any mapping key outside `allowed`; returns false if not a mapping.
function checkKeys(
  node: unknown,
  allowed: string[],
  path: string,
  errs: Violation[],
): node is Record<string, unknown> {
  if (!isRecord(node)) {
    errs.push({ path, msg: `expected a mapping, got ${node === null ? "null" : typeof node}` });
    return false;
  }
  for (const k of Object.keys(node)) {
    if (!allowed.includes(k)) {
      errs.push({ path: `${path}.${k}`, msg: `unsupported field (vz honors only: ${allowed.join(", ")})` });
    }
  }
  return true;
}

function validateContainer(c: unknown, path: string, errs: Violation[]): void {
  if (!checkKeys(c, CONTAINER_KEYS, path, errs)) return;

  if (typeof c.name !== "string" || c.name === "") {
    errs.push({ path: `${path}.name`, msg: "required, must be a non-empty string" });
  }

  const image = c.image;
  if (typeof image !== "string" || image === "") {
    errs.push({ path: `${path}.image`, msg: "required, must be a non-empty string" });
  } else if (!image.startsWith("localhost/")) {
    // push model: images are pre-seeded into local containers-storage.
    errs.push({
      path: `${path}.image`,
      msg: `must be a local image (localhost/...), got ${JSON.stringify(image)} — vz pushes images, it never pulls from a registry`,
    });
  }

  if (c.imagePullPolicy !== "Never") {
    errs.push({
      path: `${path}.imagePullPolicy`,
      msg: `must be exactly 'Never' (got ${JSON.stringify(c.imagePullPolicy)}) — the push model forbids registry pulls`,
    });
  }

  for (const key of ["command", "args"] as const) {
    if (key in c && !isStringList(c[key])) {
      errs.push({ path: `${path}.${key}`, msg: "must be a list of strings" });
    }
  }

  if ("env" in c) {
    if (!Array.isArray(c.env)) {
      errs.push({ path: `${path}.env`, msg: "must be a list" });
    } else {
      c.env.forEach((e, i) => {
        const ep = `${path}.env[${i}]`;
        if (checkKeys(e, ENV_KEYS, ep, errs) && typeof e.name !== "string") {
          errs.push({ path: `${ep}.name`, msg: "required string" });
        }
      });
    }
  }

  // ports are honored: vz apply opens them in the node firewall (hostNetwork,
  // so containerPort is the host port). Not a no-op, so it is validated strictly.
  if ("ports" in c) {
    if (!Array.isArray(c.ports)) {
      errs.push({ path: `${path}.ports`, msg: "must be a list" });
    } else {
      c.ports.forEach((p, i) => {
        const pp = `${path}.ports[${i}]`;
        if (!checkKeys(p, PORT_KEYS, pp, errs)) return;
        const cp = (p as any).containerPort;
        if (typeof cp !== "number" || !Number.isInteger(cp) || cp < 1 || cp > 65535) {
          errs.push({ path: `${pp}.containerPort`, msg: "required, integer 1-65535" });
        }
        const proto = (p as any).protocol;
        if (proto !== undefined && !PROTOCOLS.includes(proto)) {
          errs.push({ path: `${pp}.protocol`, msg: `must be one of ${PROTOCOLS.join(", ")}` });
        }
      });
    }
  }
}

// Validate a single parsed YAML document. Appends to `errs`.
export function validateManifest(doc: unknown, errs: Violation[]): void {
  if (!checkKeys(doc, POD_KEYS, "$", errs)) return;

  if (doc.apiVersion !== "v1") {
    errs.push({ path: "$.apiVersion", msg: `must be 'v1' (got ${JSON.stringify(doc.apiVersion)})` });
  }
  if (doc.kind !== "Pod") {
    errs.push({ path: "$.kind", msg: `only kind 'Pod' is supported in v3 (got ${JSON.stringify(doc.kind)})` });
  }

  if (doc.metadata === undefined) {
    errs.push({ path: "$.metadata", msg: "required" });
  } else if (checkKeys(doc.metadata, METADATA_KEYS, "$.metadata", errs)) {
    if (typeof doc.metadata.name !== "string") {
      errs.push({ path: "$.metadata.name", msg: "required, must be a string" });
    }
  }

  const spec = doc.spec;
  if (spec === undefined) {
    errs.push({ path: "$.spec", msg: "required" });
    return;
  }
  if (!checkKeys(spec, SPEC_KEYS, "$.spec", errs)) return;

  if ("hostNetwork" in spec && typeof spec.hostNetwork !== "boolean") {
    errs.push({ path: "$.spec.hostNetwork", msg: "must be a boolean" });
  }
  if (spec.restartPolicy !== undefined && !RESTART_POLICIES.includes(spec.restartPolicy as string)) {
    errs.push({ path: "$.spec.restartPolicy", msg: `must be one of ${RESTART_POLICIES.join(", ")} (got ${JSON.stringify(spec.restartPolicy)})` });
  }

  const containers = spec.containers;
  if (!Array.isArray(containers) || containers.length === 0) {
    errs.push({ path: "$.spec.containers", msg: "required, must be a non-empty list" });
    return;
  }
  const seen = new Set<string>();
  containers.forEach((c, i) => {
    const cp = `$.spec.containers[${i}]`;
    validateContainer(c, cp, errs);
    if (isRecord(c) && typeof c.name === "string") {
      if (seen.has(c.name)) {
        errs.push({ path: `${cp}.name`, msg: `duplicate container name ${JSON.stringify(c.name)}` });
      }
      seen.add(c.name);
    }
  });
}
