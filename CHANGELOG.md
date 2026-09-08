# Changelog

## 0.1.1 (2026-09-08)

- First publish to Ansible Galaxy as `mirurobotics.agent`.
- Install with `ansible-galaxy collection install mirurobotics.agent`.
- Git and GitHub Release tarball installs remain available as fallbacks.
- Tag `v*` publishes the collection tarball to Galaxy and attaches it to a
  GitHub Release.

## 0.1.0 (2026-09-06)

- Initial scaffold of the `mirurobotics.agent` collection.
- `provision` role: apt repository setup, `miru-agent` install (version is
  required and must be `0.10.2` or later; `latest` is an explicit opt-in),
  `provision --check` guard, provisioning-token flow against the Platform API
  (`Miru-Version: 2026-08-17.everglades`).
- Install `python3-debian` (required by the `deb822_repository` module).
- Validate tests (required arguments and the 0.10.2 version floor) and a
  Molecule scenario on Ubuntu 20.04, 22.04, and 24.04 that installs a
  `--check`-capable agent and asserts a fresh host exits 3. Ubuntu 20.04
  runs under ansible-core 2.16 (2.17+ cannot manage Focal's Python 3.8).
- Molecule e2e scenario that mints a provisioning token and provisions a
  device against the production API (CI uses the `MIRU_API_KEY` secret).
- GitHub-only distribution via git or the Release tarball while the
  `mirurobotics` Galaxy namespace was pending.
- Removed `miru_agent_deb_url` now that apt `stable` publishes 0.10.2.
- Removed the shipped `provision` playbook. The role is the collection
  entry point; callers choose their own inventory group.
