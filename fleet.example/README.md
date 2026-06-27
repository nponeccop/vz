# Fleet desired state (example)

This directory is a template for **the operator's own git repository** — the
single source of truth for what runs where. Its history *is* the deploy
runbook: `git log` answers "why did this change" months later. See
[`../SPEC-v3.md`](../SPEC-v3.md).

```
recipe.sh        one build recipe that produces every fleet image (2-layer base+app)
nodes/
  node-a.yaml    k8s-subset Pod manifest — the desired state for one node
```

## Workflow

```sh
# 1. Validate every manifest against the subset vz honors (stricter than podman):
node ../vztool/src/validate.ts nodes/*.yaml

# 2. Build images (writes OCI archives to ./out/):
./recipe.sh

# 3. Push + converge (step 3, not yet implemented):
#    vz apply        # push changed layers + manifest, run `podman kube play`
#    vz ps           # fleet-wide actual state
#    vz diff         # desired (this repo) minus actual
```

One Pod per file. A manifest references images as `localhost/<name>:<tag>` with
`imagePullPolicy: Never`; `recipe.sh` defines how those tags are built.
