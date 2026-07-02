# Competitors / prior art

Where vz sits relative to existing tools, by layer. vz is not a replacement for
most of these — it reuses several (Podman/runc for the runtime, `podman kube
play` for the manifest) and competes only at the fleet layer.

## Minimal-footprint rootfs

- CoreOS
- RancherOS
- PhotonOS
- Ubuntu Snap
- RedHat Atomic
- Alpine Linux
- Intel Clear Linux

## Container runners

- docker / runc
- garden / warden
- Intel Clear Containers
- udocker / proot

## Command and control (the layer vz competes in)

- fleet / etcd
- kubernetes
- Heroku
- Dokku

## Image building

- Dockerfile / Docker build / buildkit
- smith
- s2i
- Heroku
