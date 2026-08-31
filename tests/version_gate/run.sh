#!/usr/bin/env bash
# Exercise the provision role's input asserts without touching apt or the API.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

playbook=tests/version_gate/playbook.yml
export ANSIBLE_CONFIG="${root}/ansible.cfg"

run_ok() {
  local name="$1"
  shift
  echo "==> expect ok: ${name}"
  ansible-playbook "$playbook" "$@"
}

run_fail() {
  local name="$1"
  shift
  echo "==> expect fail: ${name}"
  if ansible-playbook "$playbook" "$@"; then
    echo "expected failure, playbook succeeded: ${name}" >&2
    exit 1
  fi
}

run_fail "0.10.1 is below the floor" -e test_version=0.10.1
run_fail "v0.10.1 is below the floor" -e test_version=v0.10.1
run_fail "empty version" -e test_version=""
run_fail "empty API key" -e test_version=0.10.2 -e test_api_key=""

run_ok "0.10.2" -e test_version=0.10.2
run_ok "v0.10.2 prefix is stripped" -e test_version=v0.10.2
run_ok "0.10.2-beta.1 is accepted (ansible version test)" -e test_version=0.10.2-beta.1
run_ok "0.11.0" -e test_version=0.11.0
run_ok "latest" -e test_version=latest

echo "version gate tests passed"
