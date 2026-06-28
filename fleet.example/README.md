# Fleet desired state (example)

This directory is a template for **the operator's own git repository** — the
single source of truth for what runs where. Its history *is* the deploy
runbook: `git log` answers "why did this change" months later. See
[`../SPEC-v3.md`](../SPEC-v3.md).

```
groups.yaml      topology: group -> { hosts: [IPs], pod: <path> }   (vz's format)
recipe.sh        one build recipe that produces every fleet image (2-layer base+app)
pods/
  antifraud.yaml k8s-subset Pod manifest — the workload one or more groups run
```

**Why two files.** A *Pod* describes a workload (pure Kubernetes subset,
strictly validated). *Placement* — which hosts run it — is vz's concern, kept in
`groups.yaml`. This is the Ansible split (inventory vs. playbook): the same pod
can be reused by several groups, and a host belongs to exactly one group (it
runs one pod).

## Workflow

```sh
# 1. Validate the whole fleet (topology + every referenced pod) against the
#    subset vz honors (stricter than podman):
node ../vztool/src/validate.ts groups.yaml

# 2. Build images (writes OCI archives to ./out/):
./recipe.sh

# 3. Push + converge (step 3, not yet implemented):
#    vz apply        # push changed layers + manifest, run `podman kube play`
#    vz ps           # fleet-wide actual state
#    vz diff         # desired (this repo) minus actual
```

Pods reference images as `localhost/<name>:<tag>` with `imagePullPolicy: Never`;
`recipe.sh` defines how those tags are built.
