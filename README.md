# Miru Ansible Collection

`mirurobotics.agent` — install the Miru Agent and provision devices with the Miru control plane.

For detailed documentation and usage instructions, please visit the
[official documentation](https://docs.mirurobotics.com/cfg-mgmt/provision-devices/ansible).

## Install

```bash
ansible-galaxy collection install mirurobotics.agent
```

Or pin a version in `requirements.yml`:

```yaml
collections:
  - name: mirurobotics.agent
    version: ">=0.1.1"
```

```bash
ansible-galaxy collection install -r requirements.yml
```

Git and GitHub Release tarball installs remain available as fallbacks; see
Publishing below.

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

Tag `vX.Y.Z` matching `galaxy.yml` and push. The Release workflow publishes
`mirurobotics-agent-X.Y.Z.tar.gz` to Ansible Galaxy and attaches the same
tarball to a GitHub Release.

```bash
ansible-galaxy collection install mirurobotics.agent:==X.Y.Z
```

## License

MIT
