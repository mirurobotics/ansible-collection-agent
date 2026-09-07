# Miru Ansible Collection

`mirurobotics.agent` — install the [Miru Agent](https://docs.mirurobotics.com/developers/agent/overview) and provision devices with the Miru control plane.

> **Status: 0.1.0.** Ansible Galaxy is waiting on the `mirurobotics` namespace. Install from git or the GitHub Release tarball until then.

## What it does

The `mirurobotics.agent.provision` role runs the full [provisioning-token flow](https://docs.mirurobotics.com/cfg-mgmt/provision-devices/provisioning-tokens) against every host in your play:

1. Sets up Miru's apt repository (signing key + deb822 source).
2. Installs the `miru-agent` package at the version you specify.
3. Skips hosts that are already provisioned.
4. For unprovisioned hosts, mints a short-lived provisioning token from the Platform API (on the controller — your API key never touches the devices) and runs `miru-agent provision`.

The role is idempotent: a pinned version converges every host to that package, and only unprovisioned hosts are provisioned. `miru_agent_version: latest` upgrades to the newest package on every run.

## Requirements

- ansible-core >= 2.15
- Target devices running a [supported Linux platform](https://docs.mirurobotics.com/developers/agent/install) with `systemd` and apt. ansible-core 2.17+ also needs Python 3.9+ on the target; Ubuntu 20.04 ships 3.8, so install `python3.9` on those hosts or use ansible-core 2.16.
- Miru Agent >= v0.10.2 (`provision --check` is not in earlier releases)
- A Miru [API key](https://docs.mirurobotics.com/admin/apikeys) with the `devices:provision` and `provisioning_tokens:write` scopes, available on the Ansible controller

## Install

Until the collection is on Ansible Galaxy, install from git or from a release tarball.

Git (tracks `main`):

```yaml
# requirements.yml
collections:
  - name: https://github.com/mirurobotics/ansible-collection-agent.git
    type: git
    version: main
```

```bash
ansible-galaxy collection install -r requirements.yml
```

Pinned tarball:

```bash
ansible-galaxy collection install \
  https://github.com/mirurobotics/ansible-collection-agent/releases/download/v0.1.0/mirurobotics-agent-0.1.0.tar.gz
```

Galaxy install (`ansible-galaxy collection install mirurobotics.agent`) is not enabled yet.

## Usage

Apply the role to the hosts in your inventory. Set `hosts` to your inventory group.

```yaml
- name: Provision Miru devices
  hosts: {your-inventory-group}
  roles:
    - role: mirurobotics.agent.provision
      vars:
        miru_agent_version: "0.10.2"
```

`miru_agent_version` is required and must be `0.10.2` or later. Use `latest` only when you want the newest package on every run.

Set `miru_api_key` yourself (the role does not read `MIRU_API_KEY`). Store it in [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) or inject it from your CI secret store — never commit it to inventory.

### Role variables

| Variable | Default | Description |
| --- | --- | --- |
| `miru_api_key` | — (required) | Platform API key used to mint provisioning tokens. Controller-side only. |
| `miru_agent_version` | — (required) | Agent version to install, e.g. `0.10.2`. Must be `0.10.2` or later. Use `latest` only when you want the newest package on every run. |
| `miru_device_name` | `inventory_hostname` | Device name shown in the Miru dashboard. |
| `miru_api_base_url` | `https://api.mirurobotics.com/beta` | Platform API base URL. |
| `miru_api_version` | `2026-08-17.everglades` | `Miru-Version` header sent to the Platform API. |
| `miru_apt_url` | `https://packages.mirurobotics.com/apt` | Miru apt repository. |
| `miru_apt_key_url` | `.../apt/miru.gpg` | Miru apt signing key. |
| `miru_apt_architecture` | auto-detected | Debian architecture (`amd64`, `arm64`). |
| `miru_log_secrets` | `false` | Print the API key and provisioning token in Ansible output. Leave off except for a local debug run. |

## Notes and limitations

- **Already-provisioned detection** uses `miru-agent provision --check` (exit `0` provisioned, `3` not provisioned, anything else fails the play).
- **Reprovisioning** (reassociating a machine with an existing Miru device) is a [dashboard-only flow](https://docs.mirurobotics.com/cfg-mgmt/provision-devices/reprovision) today and is out of scope for this role.
- A machine that was reprovisioned onto different hardware still holds stale local credentials and is treated as provisioned by the guard; recover via the dashboard reprovision flow.
- Verification is local (the `miru` systemd service is active). To confirm end-to-end, check the [Devices page](https://app.mirurobotics.com/devices) — devices transition `Activating` → `Online` within seconds.

## Development

```bash
pip install ansible-lint ansible-core
ansible-lint
bash tests/validate/run.sh
```

Molecule (Docker; installs `miru-agent` 0.10.2 from apt and asserts `provision --check` exits 3):

```bash
pip install ansible-core molecule "molecule-plugins[docker]"
ansible-galaxy collection install community.docker ansible.posix
molecule test
```

End-to-end Molecule mints a token and provisions a device. It needs `MIRU_API_KEY` with `devices:provision` and `provisioning_tokens:write`.

```bash
export MIRU_API_KEY=...
molecule test -s e2e
```

CI runs the e2e scenario on same-repo pulls using the `MIRU_API_KEY` repository secret. Each run creates a uniquely named device (`ci-<run-id>-...`) in the key's workspace.

### Publishing

Tag `vX.Y.Z` matching `galaxy.yml` and push. The Release workflow attaches `mirurobotics-agent-X.Y.Z.tar.gz` to a GitHub Release. Galaxy publish stays in the workflow but is skipped until the `PUBLISH_TO_GALAXY` repository variable is set to `true`.

## License

MIT
