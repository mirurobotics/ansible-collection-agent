# Changelog

## 0.1.0 (unreleased)

- Initial scaffold of the `mirurobotics.agent` collection.
- `provision` role: apt repository setup, `miru-agent` install (version is
  required; `latest` is an explicit opt-in), provisioned-state guard,
  provisioning-token flow against the Platform API
  (`Miru-Version: 2026-08-17.everglades`).
- Install `python3-debian` (required by the `deb822_repository` module).
