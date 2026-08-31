# Miru Ansible Collection

`mirurobotics.agent` — install the [Miru Agent](https://docs.mirurobotics.com/developers/agent/overview) and provision devices with the Miru control plane.

> **Status: 0.1.0.** Tag `v0.1.0` to publish to Ansible Galaxy.

## What it does

The `mirurobotics.agent.provision` role runs the full [provisioning-token flow](https://docs.mirurobotics.com/cfg-mgmt/provision-devices/provisioning-tokens) against every host in your play:

1. Sets up Miru's apt repository (signing key + deb822 source).
2. Installs the `miru-agent` package at the version you specify.
3. Skips hosts that are already provisioned.
4. For unprovisioned hosts, mints a short-lived provisioning token from the Platform API (on the controller — your API key never touches the devices) and runs `miru-agent provision`.

The role is idempotent: a pinned version converges every host to that package, and only unprovisioned hosts are provisioned. `miru_agent_version: latest` upgrades to the newest package on every run.

## Requirements

- ansible-core >= 2.15
- Target devices running a [supported Linux platform](https://docs.mirurobotics.com/developers/agent/install) with `systemd` and apt
- Miru Agent >= v0.10.2 (`provision --check` is not in earlier releases)
- A Miru [API key](https://docs.mirurobotics.com/admin/apikeys) with the `devices:provision` and `provisioning_tokens:write` scopes, available on the Ansible controller

## Install

```bash
ansible-galaxy collection install mirurobotics.agent
```

Until the first Galaxy release exists, install from git:

```yaml
collections:
  - name: https://github.com/mirurobotics/ansible-collection-agent.git
    type: git
    version: main
```

```bash
ansible-galaxy collection install -r requirements.yml
```

## Usage

```yaml
- name: Provision Miru devices
  hosts: robots
  roles:
    - role: mirurobotics.agent.provision
      vars:
        miru_api_key: "{{ vault_miru_api_key }}"
        miru_agent_version: "0.10.2"   # required, >= 0.10.2; use "latest" to float
```

Store the API key in [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) or inject it from your CI secret store — never commit it to inventory.

A ready-made playbook is included: `ansible-playbook -i inventory mirurobotics.agent.provision` targets the `robots` group.

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

Molecule (Docker; installs `miru-agent` 0.10.2-beta.1 from GitHub and asserts `provision --check` exits 3):

```bash
pip install ansible-core molecule "molecule-plugins[docker]"
ansible-galaxy collection install community.docker ansible.posix
molecule test
```

End-to-end Molecule mints a token and provisions a device. It needs `MIRU_API_KEY` with `devices:provision` and `provisioning_tokens:write`. Apt does not yet publish 0.10.2-beta.1, so the scenario installs the GitHub `.deb` and then runs the role's `provision.yml`.

```bash
export MIRU_API_KEY=...
molecule test -s e2e
```

CI runs the e2e scenario on same-repo pulls using the `MIRU_API_KEY` repository secret. Each run creates a uniquely named device (`ci-<run-id>-...`) in the key's workspace.

### Publishing

1. Create the `mirurobotics` namespace on [Ansible Galaxy](https://galaxy.ansible.com) (log in with GitHub).
2. Add a `GALAXY_API_KEY` repository secret (Galaxy → Collections → API token).
3. Tag `v0.1.0` (must match `galaxy.yml`) and push. The Release workflow builds and publishes.

## License

MIT
