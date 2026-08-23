# Miru Ansible Collection

`mirurobotics.agent` — install the [Miru Agent](https://docs.mirurobotics.com/developers/agent/overview) and provision devices with the Miru control plane.

> **Status: prototype.** Not yet published to Ansible Galaxy. Interfaces may change.

## What it does

The `mirurobotics.agent.provision` role runs the full [provisioning-token flow](https://docs.mirurobotics.com/cfg-mgmt/provision-devices/provisioning-tokens) against every host in your play:

1. Sets up Miru's apt repository (signing key + deb822 source).
2. Installs the `miru-agent` package (optionally version-pinned).
3. Skips hosts that are already provisioned.
4. For unprovisioned hosts, mints a short-lived provisioning token from the Platform API (on the controller — your API key never touches the devices) and runs `miru-agent provision`.

The role is idempotent: re-running it against a fleet installs/upgrades nothing that is already in place and only provisions hosts that need it.

## Requirements

- ansible-core >= 2.15
- Target devices running a [supported Linux platform](https://docs.mirurobotics.com/developers/agent/install) with `systemd` and apt
- Miru Agent >= v0.9.0 (provisioning tokens are not supported by earlier agents)
- A Miru [API key](https://docs.mirurobotics.com/admin/apikeys) with the `devices:provision` and `provisioning_tokens:write` scopes, available on the Ansible controller

## Install

Until the collection is published to Galaxy, install it from git via `requirements.yml`:

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
        miru_agent_version: "0.10.1"   # optional; omit for latest
```

Store the API key in [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) or inject it from your CI secret store — never commit it to inventory.

A ready-made playbook is included: `ansible-playbook -i inventory mirurobotics.agent.provision` targets the `robots` group.

### Role variables

| Variable | Default | Description |
| --- | --- | --- |
| `miru_api_key` | — (required) | Platform API key used to mint provisioning tokens. Controller-side only. |
| `miru_agent_version` | `""` (latest) | Agent version to install, e.g. `0.10.1`. |
| `miru_device_name` | `inventory_hostname` | Device name shown in the Miru dashboard. |
| `miru_api_base_url` | `https://api.mirurobotics.com/beta` | Platform API base URL. |
| `miru_api_version` | `2026-05-06.rainier` | `Miru-Version` header sent to the Platform API. |
| `miru_apt_url` | `https://packages.mirurobotics.com/apt` | Miru apt repository. |
| `miru_apt_key_url` | `.../apt/miru.gpg` | Miru apt signing key. |
| `miru_apt_architecture` | auto-detected | Debian architecture (`amd64`, `arm64`). |
| `miru_provision_no_log` | `true` | Hide tokens from logs. Set `false` briefly to debug a failing provision. |

## Notes and limitations

- **Already-provisioned detection** currently checks for device credentials under `/var/lib/miru/auth/`. It will move to a first-class `miru-agent provision --check` command when the agent ships one.
- **Reprovisioning** (reassociating a machine with an existing Miru device) is a [dashboard-only flow](https://docs.mirurobotics.com/cfg-mgmt/provision-devices/reprovision) today and is out of scope for this role.
- A machine that was reprovisioned onto different hardware still holds stale local credentials and is treated as provisioned by the guard; recover via the dashboard reprovision flow.
- Verification is local (the `miru` systemd service is active). To confirm end-to-end, check the [Devices page](https://app.mirurobotics.com/devices) — devices transition `Activating` → `Online` within seconds.

## Development

```bash
pip install ansible-lint
ansible-lint
```

## License

MIT
