# vz bootstrap on OVH / ESXi — plan

## Why this exists

The real goal is to **resume work on an existing project whose deployment scheme is
fragile**, by making `vz` good enough to actually deploy it. `vz` today is unfinished and
unusable: the end-to-end bootstrap never ran cleanly — it always had to be pushed through by
hand, failing on bugs like referencing files that aren't there. Likely some code rot now that
Rocky 10 is current.

Everything else here is low-hanging fruit that's useful to others (and to us) even if only
partly finished:
- Mass-produce ansible-managed Rocky nodes on one Kimsufi/ESXi box ($17/mo, 32 GB / 2 TB) to
  consolidate all projects onto a single dedicated server.
- A reusable "Rocky anywhere" bootstrap that works on any provider, not just ESXi.

**Definition of done for the prize: `vz` can push an image to a freshly bootstrapped node.**
Not reboot-survival, not a running pod — a successful push.

---

## The handoff contract

Every layer below the bootstrap exists only to produce one thing:

> **a clean Rocky system, reachable as `root` over SSH with the CAPI key authorized, on a
> working network.**

That is exactly what a VPS provider hands you. Once the key is present, **ansible takes over** —
nothing above this line needs to know how the VM was born. This is the seam that keeps the
design portable across ESXi, DigitalOcean, Vultr, and bare-VPS providers that offer no
cloud-init at all.

---

## Layers

### Layer 1 — VM provisioning → the handoff contract
**ESXi-only for now; DigitalOcean / Vultr later. Bonus, not the prize.**

Produces a clean Rocky VM satisfying the handoff contract.

- Use **Rocky cloud images + cloud-init**, not the interactive ISO installer.
- cloud-init is kept **deliberately minimal** — it only synthesizes the provider handoff:
  inject the CAPI public key for `root`, ensure networking. It does **not** create users, sudo,
  or install packages — that's ansible's job, so the same ansible runs identically on a
  bare-VPS provider that has no cloud-init.
- On ESXi: download the Rocky cloud image to `datastore1`, seed cloud-init via a config ISO
  (or guestinfo), create the VM with `vim-cmd`, power on.
- Manual / OVH-API steps that stay out of band: ordering the server, ordering an extra IP,
  reverse DNS. (See OVH note below.)

### Layer 2 — `bootstrap.sh` → manageable node  ★ THE FOCUS ★
**ESXi-agnostic. This is what's broken and what unblocks the prize.**

`bootstrap.sh` remains the artifact (portable: works wherever the handoff contract holds).
Its job: take a clean Rocky-with-key and make it a node `vzmaster` can drive.

- **Mandate: every imperative step moves into idempotent ansible**, so a failed run is safely
  re-runnable from any partial state. Fragility was non-idempotency + missing-file bugs.
- Existing `bootstrap.yaml` already targets RHEL/Rocky (EPEL, sudo role) — fix and harden it,
  do **not** rewrite for another distro.
- Audit for Rocky 10 rot (EPEL repo name, `libselinux-python` → `python3-libselinux`, etc.).
- End state: `ansible <node> -m ping` green (while admin attached) and the node has whatever
  `vzmaster push` requires (podman + runch/vzexec deployed).

### Layer 3 — podman ops under `vzmaster`
**ESXi-agnostic. The actual end the real project migrates onto.**

- `vzmaster push/start/kill` over SSH; image transfer over SFTP; node-local supervision via
  `runch`/`vzexec`.
- Debug podman/container builds (never done end-to-end before).
- Everything constrained by the sleeping-plane paradigm below.

---

## Sleeping-plane paradigm (security invariant)

**The control plane is dead whenever the admin is detached.** The master holds only *public*
keys; the CAPI *private* key lives in the admin's Windows cert store / YubiKey and is reachable
only via a live forwarded SSH agent with HITL confirmation (pageant + YubiKey touch). Think of
the forwarded agent as a smart card: present while working, gone on detach.

Consequences — we implement **only** what holds under this assumption:
- **No** autoscaling, failover, crash-rescheduling, or central monitoring. A node that dies at
  3am stays dead until the admin logs in.
- Features get re-imagined as **on-demand-over-SSH**, not 100%-uptime web panels — e.g. the
  admin pulls charts over SSH when attached.
- A **node-local supervisor is allowed** (restart a container on the same box), but it may
  **not** coordinate with other nodes — inter-node action is the control plane, which is
  forbidden while asleep.
- Monitoring is out of scope: the deployed app is observed by app-specific, out-of-band means.

This is still a lot — it's a declarative, apply-on-attach version of the
Kubernetes/Dokku/Heroku idea, minus the always-on controller.

---

## Access model — LLM-first iteration

The agent is given enough standing tooling to run a tight edit→provision→bootstrap→observe loop
without a human in every cycle.

| Surface | How the agent acts | Notes |
|---|---|---|
| ESXi root | Forwarded CAPI agent over SSH | Only while admin attached. Within the security model. |
| Scratch slave VM | `vim-cmd` create/destroy on `datastore1` | **Blessed disposable VM** — the core debug loop for Layer 2. Recreate at will. |
| OVH API | `ovhcloud` CLI, creds in `~/.ovh.conf` | **The one accepted-insecure surface.** OVH has no RSA/ECDSA-authenticated API to port onto an SSH agent, so there is no secure design. Touched **only during cluster changes** (order server/IP, reverse DNS), so it doesn't violate "offline control plane." |
| GitHub / CICD | `gh` CLI | Monitor CICD and push bootstrap fixes; commit identity comes from the authenticated user. |
| repo | git push | Fork or direct push, per the contributor's rights. |

**The accelerator:** the disposable scratch VM turns "rebuild the box by hand" into an
autonomous loop. That, plus `gh` for CICD feedback, is what makes iterating `bootstrap.sh` to
flawless actually fast.

### Setting up the OVH CLI (any OVH account)

OVH's API endpoint follows the **account's** OVH entity, *not* the physical server location.

1. Install: `curl -fsSL https://raw.githubusercontent.com/ovh/ovhcloud-cli/main/install.sh | sh`
   (installs to `~/.local/bin/ovhcloud` — add it to `PATH`).
2. `ovhcloud login` — interactive; **needs a real TTY** (won't run through Claude Code's `!`
   prefix, which has no `/dev/tty`). It generates the App Key / Secret / Consumer Key and writes
   `~/.ovh.conf`.
3. Pick the endpoint matching your account: `ovh-eu` (Europe), `ovh-ca` (Canada),
   `ovh-us` (US), `soyoustart-eu`, etc. If reads work but a later write 404s, the account may
   live on a different entity — re-login against the other endpoint.
4. Verify: `ovhcloud account get` and `ovhcloud baremetal list`.

---

## Workstreams, reprioritized

| # | Work | Layer | Priority | Blocker |
|---|------|-------|----------|---------|
| 1 | Stand up disposable Rocky scratch VM on ESXi via cloud-init | 1 | **First** — needed to test everything else | Download Rocky cloud image to datastore1 |
| 2 | Fix + idempotent-ify `bootstrap.yaml`; debug to flawless | 2 | **The prize** | Rocky 10 rot audit; scratch VM |
| 3 | Get `vzmaster push` to succeed end-to-end | 3 | Definition of done | 2 done |
| 4 | Migrate the real project onto the new infra | — | The actual point | 3 done |
| 5 | Generalize Layer 1 to DigitalOcean / Vultr | 1 | Bonus | 2–3 stable |
| 6 | OVH API automation (order server/IP, reverse DNS) | 0 | Bonus | `ovhcloud` CLI configured |

---

## Decisions

- `gh` authenticated; OVH CLI configured (`~/.ovh.conf`).
- **Rocky 9** is the target — its cloud images and cloud-init datasource are well-trodden.
  Get the bootstrap flawless on 9 before considering Rocky 10.
- Direct push to the repo (no fork).
