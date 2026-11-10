# Code quality assessment of the ansible-collection-agent repo

An audit of `mirurobotics/ansible-collection-agent` at `ebb26e2` (2026-11-10): where the `mirurobotics.agent` collection, its tests, CI and release fall short, and what to do about it, in priority order. It changes no code. Each finding is meant to become its own ExecPlan in `plans/active/` when picked up. (The repo has no `plans/` tree yet; this doc starts one, matching the layout in the other Miru repos.)

## How to read this

Each finding gives what is wrong, why it matters, and a suggested fix, with a rough effort (S: under a day, M: a few days, L: a week or more).

- **P1: fix first.** Something the collection ships or publishes is wrong today, or can change without a commit in this repo.
- **P2: fix soon.** Test gaps, hidden failures and fragile steps that make each change or rollout riskier.
- **P3: tidy up.** Packaging, docs and hygiene gaps that are cheap to close.

| # | Finding | Priority | Effort |
|---|---------|----------|--------|
| 1 | `v`-prefixed versions pass validation, then break the apt install | P1 | S |
| 2 | `--check` (dry run) fails on every host that isn't provisioned yet | P1 | S |
| 3 | Any tag publishes to Galaxy untested, and a failed publish can't be retried | P1 | M |
| 4 | Every tool, test image and test collection floats to "latest" | P1 | S |
| 5 | No test runs the role the way users do | P2 | M |
| 6 | Only agent 0.10.2 on amd64 Ubuntu is ever tested, and nothing runs on a schedule | P2 | M |
| 7 | API errors are hidden by `no_log` | P2 | S |
| 8 | A version pin can't be rolled back, and nothing holds it | P2 | S |
| 9 | The apt signing key is trusted from whatever the URL serves | P2 | S |
| 10 | The required e2e check runs against production and leaves devices behind | P2 | M |
| 11 | No collection-level checks before release (`ansible-test sanity`, Galaxy import) | P2 | S |
| 12 | The published tarball ships `dist/`, tests and dev config | P3 | S |
| 13 | Role variables are only documented outside the repo, and defaults are written twice | P3 | S |
| 14 | Role details: internal variable names, architecture mapping, support policy | P3 | S |
| 15 | Duplicated Molecule config and verify tasks | P3 | S |
| 16 | CI and repo hygiene | P3 | S |

## What is already good

These are worth keeping as the repo changes:

- Every third-party action is pinned to a commit SHA, and Dependabot keeps them current. The CI token is `contents: read`, and the Slack `notify` job runs with `permissions: {}`.
- Branch protection (in `mirurobotics/infra` `github/terraform/repos.tf`) requires `ai-review`, `e2e`, `lint`, `molecule-result` and `test`. The `molecule-result` aggregate keeps the required check stable while the matrix changes.
- The API key never leaves the controller: the token is minted with `delegate_to: localhost` and `become: false`, both secret-bearing tasks are `no_log`, and the token reaches the agent through an environment variable rather than `argv`.
- Provisioning is idempotent by design. `provision --check` has documented exit codes (0, 3, anything else fails the play), `molecule test` runs its idempotence step, and the e2e verify re-runs `provision.yml` on a provisioned host to prove no second token is minted.
- Inputs are checked twice: `meta/argument_specs.yml` types and documents every option, and `validate.yml` adds clear messages for the required values and the 0.10.2 floor, with 11 cases in `tests/validate/run.sh`.
- `ansible-lint` passes the `production` profile with no warnings, and the one skipped rule is explained in `.ansible-lint`.
- The release checks that the tag matches `galaxy.yml`, and non-obvious choices (the Ubuntu 20.04 controller pin, the `GITHUB_RUN_ID` device name) are explained in comments.

---

## P1: fix first

### 1. `v`-prefixed versions pass validation, then break the apt install

**What.** `validate.yml` strips a leading `v` before the version-floor check (`regex_replace('^[vV]', '')`), and `tests/validate/run.sh` asserts that `v0.10.2` is accepted ("v0.10.2 prefix is stripped"). But `install.yml` uses the raw value: `name: "miru-agent={{ miru_agent_version }}"`, so `miru_agent_version: v0.10.2` asks apt for `miru-agent=v0.10.2`, which doesn't exist. The validate test only runs `validate.yml`, so it passes while the real run fails. Pre-release strings like `0.10.2-beta.1` are also accepted, but whether apt has a package with that exact version string depends on how the agent's `.deb` versions are written (Debian usually spells pre-releases `0.10.2~beta.1`). The apt repo wasn't reachable from the audit environment, so this was not checked.

**Why it matters.** Agent release tags are `vX.Y.Z`, so copying a tag into inventory is the most likely mistake, and the role tells the user it's fine before failing on every host in the apt step.

**Fix.** Normalise once, in `validate.yml`: `set_fact: miru_agent_package_version: "{{ miru_agent_version | regex_replace('^[vV]', '') }}"`, and use that in `install.yml`. Decide whether pre-release strings are supported; if they are, map them to the `.deb` spelling, and if not, reject them with a clear message. Add a Molecule case that installs with `v0.10.2` (see #5) so the test covers the install, not just the assert.

### 2. `--check` (dry run) fails on every host that isn't provisioned yet

**What.** Two failures, both reproduced with a stub `miru-agent` on localhost:

- On a fresh host, `install.yml` doesn't install anything in check mode, but the `provision --check` task has `check_mode: false` and runs `/usr/sbin/miru-agent`, which isn't there. The command returns rc 2, which `failed_when: miru_check.rc not in [0, 3]` turns into a failure.
- On an installed but unprovisioned host, the `uri` task is skipped in check mode, so `miru_token_response` has no `json`. The next task fails with `Error processing keyword 'environment': object of type 'dict' has no attribute 'json'`, and because the task is `no_log`, the user only sees "the output has been hidden".

**Why it matters.** `ansible-playbook --check --diff` is how people preview a fleet rollout, and onboarding new devices is the main use of this role. Today the preview fails on exactly those hosts, with no useful error.

**Fix.** Stat `/usr/sbin/miru-agent` first and skip the check when it's absent in check mode (treat as "would install and provision"). Skip the provisioning block in check mode (`when: not miru_provisioned and not ansible_check_mode`), and add a `debug` task that says "would provision <name>" instead. Run the Molecule converge once with `--check` in CI so this stays fixed.

### 3. Any tag publishes to Galaxy untested, and a failed publish can't be retried

**What.**

- `release.yml` runs on any `v*` tag push. It doesn't check that the tag is on `main`, and it runs no lint or tests before publishing. `repos.tf` defines no tag ruleset and no protected environment for this repo, so anyone with write access can publish any commit.
- The job creates the GitHub Release first and publishes to Galaxy second. If the Galaxy step fails, the GitHub Release already exists, and re-running the job fails at `gh release create`. This has already happened: `v0.1.1` is a GitHub Release whose notes say `ansible-galaxy collection install mirurobotics.agent:==0.1.1`, but the Galaxy import failed ("No role readme found", per `CHANGELOG.md`), so that command never worked.
- `contents: write` is granted to the whole workflow, and `GALAXY_API_KEY` is a plain repository secret, so a workflow on any pushed branch can read it.
- The release notes are only install commands; `CHANGELOG.md` isn't used or checked for an entry for the new version.

**Why it matters.** Galaxy versions are permanent: a broken or wrong upload can't be replaced, only superseded. Every fleet that runs `ansible-galaxy collection install mirurobotics.agent` without a pin picks it up.

**Fix.** Add a first job that checks `git merge-base --is-ancestor "$GITHUB_SHA" origin/main` and runs the same lint, validate and sanity checks as CI (or `needs` a reusable CI workflow). Publish to Galaxy first, then create the GitHub Release, or create the GitHub Release as a draft and publish it only after Galaxy succeeds; make the `gh release create` step tolerate an existing draft so a re-run works. Put `GALAXY_API_KEY` in a `release` environment restricted to `v*` tags, and add a tag ruleset in `repos.tf`. Use the matching `CHANGELOG.md` section as the release body, and fail if it's missing. Edit the `v0.1.1` release notes to say it never reached Galaxy.

### 4. Every tool, test image and test collection floats to "latest"

**What.**

- CI and the release job run `pip install ansible-lint ansible-core`, `molecule` and `molecule-plugins[docker]` with no versions. There is no `requirements*.txt` or lock file, so Dependabot can't see them. The audit environment resolved ansible-core 2.22.0 and ansible-lint 26.11.0.
- `ansible-galaxy collection install community.docker ansible.posix` has no versions and no `requirements.yml`.
- Molecule uses `geerlingguy/docker-${MOLECULE_DISTRO}-ansible:latest`, a third-party image, run `privileged: true` with the host cgroup mounted.

**Why it matters.** The published tarball is built by whatever ansible-core PyPI serves on tag day. A new ansible-lint release can add rules and turn the required `lint` check red on a PR that touched nothing. A new upstream test image or `community.docker` release can do the same for `molecule-result`. A compromised third-party image would run privileged on the CI runner.

**Fix.** Add `requirements-dev.txt` (or a `pyproject.toml` with a lock) pinning `ansible-core`, `ansible-lint`, `molecule` and `molecule-plugins`, and a separate pin for the Ubuntu 20.04 cell. Add `molecule/requirements.yml` with pinned collection versions (Molecule's `dependency` step installs it). Pin the test images by digest, or build small images from the official `ubuntu:*` digests in this repo. Add `pip` and `docker` ecosystems to `.github/dependabot.yml`.

---

## P2: fix soon

### 5. No test runs the role the way users do

**What.**

- Users call `roles: [mirurobotics.agent.provision]`, which runs `tasks/main.yml` and validates `meta/argument_specs.yml`. Every test instead uses `include_role` with `tasks_from:` (`validate.yml`, `repo.yml`, `install.yml`, `provision.yml`), and argument specs only apply to the `main` entry point. So `main.yml`, the argument-spec validation and the task order are never run in CI.
- Tests find the role by short name through `roles_path`, not as `mirurobotics.agent.provision` from the built collection, so a packaging mistake (like the missing README in 0.1.1) can't be caught.
- Molecule's Docker connection runs as root. Fleets usually connect as a normal user with `sudo`, and then `become_user: miru` needs the `acl` package (or pipelining) to hand temp files to `miru`. The role installs neither, and that path is untested.
- `tests/validate/run.sh` covers the asserts in isolation, which is how #1 slipped through.

**Why it matters.** The tests prove the pieces work, not the product. A broken `main.yml`, an argument-spec mistake, or a packaging gap ships green.

**Fix.** Make the default Molecule converge `ansible-galaxy collection install` the tarball built in the same job and run `roles: [mirurobotics.agent.provision]` end to end, with the token mint pointed at a local stub (a tiny HTTP server in a `prepare` step, or `miru_api_base_url` aimed at a sidecar container) so it stays offline. Add a platform that connects as a non-root user with sudo. Keep `tests/validate/run.sh` for fast input checks, but add the `v0.10.2` and pre-release cases to Molecule.

### 6. Only agent 0.10.2 on amd64 Ubuntu is ever tested, and nothing runs on a schedule

**What.**

- `MOLECULE_AGENT_VERSION` defaults to `0.10.2` and CI never sets it, so every run installs the oldest supported agent. The `latest` path (`state: latest`) is never tested.
- All runs are on amd64. Robots are mostly arm64, and the `aarch64 -> arm64` mapping in `defaults/main.yml` is untested.
- `meta/main.yml` lists Debian (`all`) as supported, but no Debian image is tested.
- CI only runs on PRs and pushes. The role depends on things that change without a commit here: the apt repo, the agent package, the API at `miru_api_version: 2026-08-17.everglades`, and the upstream test images.

**Why it matters.** A new agent release that changes `provision --check` output or exit codes, or an arm64 packaging issue, would reach users before this repo noticed.

**Fix.** Add a nightly `schedule` run of the Molecule matrix with `MOLECULE_AGENT_VERSION=latest`, plus an `ubuntu-24.04-arm` runner cell, and a Debian 12 cell (or drop Debian from `meta/main.yml` until it's tested). Post nightly failures to Slack the way the release does.

### 7. API errors are hidden by `no_log`

**What.** The token mint (`uri`) and provision (`command`) tasks are `no_log` unless `miru_log_secrets` is true. Any failure, such as a wrong key (401), a key without `provisioning_tokens:write` (403), a rate limit, a network error or an unexpected response shape, shows only `"censored": "the output has been hidden..."`. Checked with an unreachable API URL: the real cause (`Status code was -1 ... Connection refused`) only appears with `miru_log_secrets=true`, which the docs say not to use in CI. `status_code: 200` also fails if the API ever answers `201`.

**Why it matters.** The only way to debug a failed rollout is to turn on secret logging, which puts the API key in the log of the very run you're debugging.

**Fix.** Keep `no_log` on the request, but add `failed_when: false`, then a non-secret `assert` that `miru_token_response.status` is 200 or 201 and fails with the status code and the API's error message (not the headers or the token). Do the same for `provision`: register its result with `no_log`, then report `rc` and `stderr` after removing the token. Then `miru_log_secrets` is rarely needed.

### 8. A version pin can't be rolled back, and nothing holds it

**What.** `install.yml` uses `state: present` with `miru-agent=<version>` and doesn't set `allow_downgrade`. Lowering the pin (for example 0.11.0 back to 0.10.2) makes apt refuse to downgrade, so the play fails. Nothing puts the package on hold, so a manual `apt upgrade` on a device moves it off the pin, and the next role run then fails the same way. `update_cache` only runs when the repo definition changed, and the prerequisite step's `cache_valid_time: 3600` means a pin to a version published in the last hour can fail with "no package matching" on hosts that ran the role recently.

**Why it matters.** The argument spec says the pin exists "so every host in a fleet converges to the same package". Today it only converges upward, and rolling back a bad agent release is exactly when you need it to work.

**Fix.** Set `allow_downgrade: true` when a version is pinned, and hold the package (`ansible.builtin.dpkg_selections: name=miru-agent selection=hold` when pinned, `install` when `latest`). Refresh the apt cache when the requested version isn't in it (for example, check `apt-cache policy` output, or set `cache_valid_time` low on the install task). Add a Molecule step that pins up and then back down.

### 9. The apt signing key is trusted from whatever the URL serves

**What.** `deb822_repository` is given `signed_by: "{{ miru_apt_key_url }}"`, so the module downloads the key over HTTPS and trusts whatever it gets. There's no fingerprint check, and both the key and the packages come from `packages.mirurobotics.com`.

**Why it matters.** Anyone who can change files on that host (or on a mirror a user points `miru_apt_url` and `miru_apt_key_url` at) can swap the key and the packages together, and every fleet running the role would install the result as root.

**Fix.** Ship the public key in the collection (`roles/provision/files/miru-archive-keyring.asc`) and pass its contents to `signed_by`, or download it with `get_url` and check its fingerprint against a pinned `miru_apt_key_fingerprint` before use. Keep the URL option for people who mirror the repo, but require the fingerprint with it. Document the key rotation process.

### 10. The required e2e check runs against production and leaves devices behind

**What.** The `e2e` job mints a token and provisions a device against `https://api.mirurobotics.com/beta` on every same-repo PR and every push to `main`, using the `MIRU_API_KEY` repository secret. The README notes each run "creates a uniquely named device ... in the key's workspace", and there's no Molecule `cleanup` or `destroy` step that deletes it. `e2e` is a required check, so a production API outage blocks every merge, and code on every same-repo branch runs with a production key.

**Why it matters.** The workspace fills with `ci-<run-id>-...` devices (one per run, so hundreds a year), and the key is a production credential with write scopes available to every PR branch.

**Fix.** Delete the device in a Molecule `cleanup` playbook (look it up by name and call the API's delete endpoint), or run a scheduled job that deletes `ci-*` devices older than a day. Use a dedicated CI workspace and a key scoped to it, stored in a GitHub environment. Consider making e2e required only on `main` and the nightly run (#6), with PRs relying on the offline stub from #5.

### 11. No collection-level checks before release (`ansible-test sanity`, Galaxy import)

**What.** CI runs `ansible-lint` and `ansible-galaxy collection build`, but not `ansible-test sanity` or the Galaxy importer (`galaxy-importer`), which is what failed for 0.1.1. The build output isn't inspected (see #12).

**Why it matters.** Galaxy import rules are the last gate, and they only run after the version is spent (#3).

**Fix.** Add a `collection` CI job that builds the tarball, runs `python -m galaxy_importer.main <tarball>` and `ansible-test sanity --docker` from an `ansible_collections/mirurobotics/agent` checkout, and fails on any import warning. Make it a required check in `repos.tf` and run it in the release workflow before publishing.

---

## P3: tidy up

### 12. The published tarball ships `dist/`, tests and dev config

**What.** `build_ignore` lists only `.github`, `molecule` and `*.tar.gz`. The `v0.1.3` tarball on GitHub contains an empty `dist/` (the release builds with `--output-path dist` inside the repo), `tests/validate/`, `ansible.cfg`, `.ansible-lint` and `.gitignore`. A local build after `ansible-lint` also picks up its `.ansible/` cache, a nested copy of the whole collection; the CI `lint` job builds right after `ansible-lint`, so the tarball it checks has this too.

**Fix.** Add `dist`, `.ansible`, `tests`, `ansible.cfg`, `.ansible-lint`, `.gitignore` and `plans` to `build_ignore` (or use `manifest:` with explicit includes). Build to a path outside the checkout in the release job. In the job from #11, list the tarball and compare it to an expected file list.

### 13. Role variables are only documented outside the repo, and defaults are written twice

**What.** `README.md` and `roles/provision/README.md` link to docs.mirurobotics.com for usage and variables. The in-repo source of truth is `meta/argument_specs.yml`, but each default (`miru_api_base_url`, `miru_api_version`, the apt URLs) is written in both it and `defaults/main.yml`, and nothing checks they match. `README.md`'s development section installs unpinned tools.

**Fix.** Generate the role README's variable table from `argument_specs.yml` (or point to `ansible-doc -t role mirurobotics.agent.provision`, which renders it). Add a small check in `tests/` that every key in `defaults/main.yml` has the same default in the argument spec. Update the development section once #4 adds requirements files.

### 14. Role details: internal variable names, architecture mapping, support policy

**What.**

- Registered and internal variables (`miru_check`, `miru_provisioned`, `miru_token_response`, `miru_apt_repo`, `miru_service_check`) use the same `miru_` prefix as user-facing options, so users can't tell them apart and could collide with them.
- `miru_apt_architecture` maps `x86_64` and `aarch64` and passes anything else through, so an `armv7l` host gets `Architectures: armv7l`, which apt ignores, and the install then fails with "no package matching" instead of a clear message.
- `meta/runtime.yml` says `requires_ansible: ">=2.15.0"`, but CI tests 2.16 (Ubuntu 20.04 cell) and latest. ansible-core 2.15 and 2.16 and Ubuntu 20.04 standard support are all past end of life.
- `miru_device_name` defaults to `inventory_hostname`, which is often an IP address in fleet inventories.

**Fix.** Prefix internal variables with `__miru_` (and keep the `var-naming` skip as it is). Fail early in `validate.yml` when the architecture isn't one the apt repo publishes. Pick a support policy (for example, ansible-core versions still supported upstream, Ubuntu LTS releases in standard support), set `requires_ansible` and the matrix from it, and record it in the README. Mention the `inventory_hostname` default in the docs.

### 15. Duplicated Molecule config and verify tasks

**What.** `molecule/default/molecule.yml` and `molecule/e2e/molecule.yml` repeat the same driver, platform and provisioner blocks. The `provision --check` command is written out four times (`provision.yml`, both `verify.yml` files) with the same `become_user`, `failed_when` and argv. `e2e/converge.yml` re-asserts `miru_api_key` before calling `validate.yml`, which asserts it again.

**Fix.** Move the shared parts into `.config/molecule/config.yml` (Molecule merges it into each scenario). Put the check in `roles/provision/tasks/check.yml` and include it from the role and the verify playbooks. Once #5 runs the full role, the e2e converge becomes a plain `roles:` call.

### 16. CI and repo hygiene

**What.**

- No job sets `timeout-minutes`, and `ci.yml` has no `concurrency` group, so superseded PR pushes keep running Molecule and e2e (which provisions a device each time, #10).
- `ansible.posix` is installed in CI and the README but nothing in the repo uses it.
- `CHANGELOG.md` is hand-written and not checked against `galaxy.yml` (see #3).
- `.github/CODEOWNERS` names one person, so one absence blocks every merge.

**Fix.** Add `timeout-minutes` to every job and a `concurrency` group with `cancel-in-progress` for PRs. Drop `ansible.posix` (or add it to `requirements.yml` with a comment if Molecule needs it). Add a CI check that `CHANGELOG.md` has a section for the `galaxy.yml` version. Add a second code owner.

---

## Suggested order

1. **Correctness first, each a small PR:** #1 (version prefix), #2 (check mode), #7 (visible API errors).
2. **Make releases safe:** #4 (pins), then #11 and #12 (collection checks and packaging), then #3 (release workflow), which reuses the checks from #11.
3. **Test the product, not the pieces:** #5, then #6 on top of it, then #10 once the offline stub from #5 exists.
4. **Rollout safety:** #8 and #9.
5. **Hygiene, any time:** #13, #14, #15, #16.

## How this was checked

The whole repo was read at `ebb26e2`. `ansible-lint` 26.11.0 (ansible-core 2.22.0) passes the `production` profile with no warnings, and `tests/validate/run.sh` passes. `ansible-galaxy collection build` was run locally and the `v0.1.3` release tarball was downloaded and listed for #12. The check-mode failures in #2 and the hidden API error in #7 were reproduced on localhost with a stub `/usr/sbin/miru-agent` and an unreachable API URL. Argument-spec validation was run with `-vvv` to confirm it doesn't print `miru_api_key`. Branch protection was read from `mirurobotics/infra` `github/terraform/repos.tf`. Molecule and e2e were not run (the audit environment had no Docker daemon and no route to the apt repo), and `packages.mirurobotics.com` and Galaxy weren't reachable, so the `.deb` version format in #1 and the Galaxy version list in #3 were not checked directly.
