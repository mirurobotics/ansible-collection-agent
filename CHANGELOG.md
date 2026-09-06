# Changelog

## 0.1.0 (unreleased)

- Initial scaffold of the `mirurobotics.agent` collection.
- `provision` role: apt repository setup, `miru-agent` install (version is
  required and must be `0.10.2` or later; `latest` is an explicit opt-in),
  `provision --check` guard, provisioning-token flow against the Platform API
  (`Miru-Version: 2026-08-17.everglades`).
- Install `python3-debian` (required by the `deb822_repository` module).
- Validate tests (required arguments and the 0.10.2 version floor) and a
  Molecule scenario that installs a `--check`-capable agent and asserts a
  fresh host exits 3.
- Molecule e2e scenario that mints a provisioning token and provisions a
  device against the production API (CI uses the `MIRU_API_KEY` secret).
- Install from git or the GitHub Release tarball. Tag `v*` attaches the
  tarball to a GitHub Release. Galaxy publish is present in the workflow
  but skipped until `PUBLISH_TO_GALAXY` is enabled.
- Removed `miru_agent_deb_url` now that apt `stable` publishes 0.10.2.
