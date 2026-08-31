# Changelog

## 0.1.0 (unreleased)

- Initial scaffold of the `mirurobotics.agent` collection.
- `provision` role: apt repository setup, `miru-agent` install (version is
  required and must be `0.10.2` or later; `latest` is an explicit opt-in),
  `provision --check` guard, provisioning-token flow against the Platform API
  (`Miru-Version: 2026-08-17.everglades`).
- Install `python3-debian` (required by the `deb822_repository` module).
