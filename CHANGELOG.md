# Changelog

## 0.1.0 (unreleased)

- Initial scaffold of the `mirurobotics.agent` collection.
- `provision` role: apt repository setup, `miru-agent` install with optional
  version pinning, provisioned-state guard, provisioning-token flow against
  the Platform API.
- `miru_provision` toggle for install-only runs (image baking); no API key
  required in that mode.
- Install `python3-debian` (required by the `deb822_repository` module).
- Molecule test scenario (offline, systemd containers) and CI matrix over
  Ubuntu 22.04/24.04.
