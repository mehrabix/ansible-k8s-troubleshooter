# ansible-k8s-troubleshooter

An **Ansible** project that automates a Kubernetes troubleshooting scenario end
to end — and does it per environment with **Jinja2-templated manifests** and
**Ansible Vault**.

Where Terraform *provisions* a desired state, Ansible is at its best running a
**sequence of steps and asserting the outcome**. This project leans into that:
it deliberately *breaks* a workload, proves it is broken, diagnoses it, applies
the fix, and proves it recovered — all from one playbook.

## The scenario loop

```
Phase 0  create the namespace and Service
Phase 1  deploy the workload WITHOUT its configuration   -> reproduce the failure
         assert: restartCount > 0, lastState Error, exit 1
Phase 2  run the on-call diagnosis (describe, logs --previous)
Phase 3  apply the fix (create the Secret, redeploy with the config)
Phase 4  assert recovery (readyReplicas == replicas)
```

Every phase both **acts** and **asserts**, so the playbook is an executable
runbook and a test of the cluster's behaviour at the same time.

## Environments and secrets (D)

| | `dev` | `prod` |
|---|---|---|
| variables | [`vars/dev.yml`](vars/dev.yml) | [`vars/prod.yml`](vars/prod.yml) |
| replicas | 1 | 2 |
| resources | smaller | larger |
| `database_url` | a throwaway value in `vars/dev.yml` | **from Ansible Vault** (`vault/secrets.yml`) |

`vars/prod.yml` intentionally does **not** contain `database_url`. When the
environment does not define it, the play loads it from the encrypted vault:

```yaml
- name: Load credentials from Ansible Vault (only when the env has none)
  ansible.builtin.include_vars:
    file: "{{ playbook_dir }}/../vault/secrets.yml"
  when: database_url is not defined
  no_log: true
```

The manifests are Jinja2 templates (`roles/crashloop/templates/*.j2`) driven by
those variables — the same template renders a 1-replica dev workload and a
2-replica prod workload.

## Repository layout

```
ansible-k8s-troubleshooter/
├── ansible.cfg
├── inventory/
│   ├── hosts.ini
│   └── group_vars/all.yml        # shared vars (env, lab_namespace, app_name, ...)
├── vars/{dev,prod}.yml           # per-environment values
├── vault/secrets.yml.example     # copy it + encrypt with your own password
├── roles/crashloop/
│   ├── tasks/main.yml            # the phase 0-4 loop
│   ├── handlers/main.yml         # "Restart the deployment" on config change
│   ├── templates/*.j2            # Jinja2 manifests
│   └── defaults/main.yml
├── playbooks/{run-scenario,teardown}.yml
├── Makefile
└── .github/workflows/ci.yml      # ansible-lint + --syntax-check
```

## Prerequisites

- `ansible-core` >= 2.15
- `kubernetes.core` collection: `ansible-galaxy collection install -r requirements.yml`
- the Python `kubernetes` client **in the same Python that runs Ansible**
  (`pip install kubernetes` — for a venv install, use that venv's pip)
- a Kubernetes cluster reachable via kubeconfig

## Usage

```bash
# one-time: create the encrypted credentials file with YOUR OWN password
cp vault/secrets.yml.example vault/secrets.yml
openssl rand -hex 16 > .vault_pass          # your vault password (gitignored)
ansible-vault encrypt vault/secrets.yml --vault-password-file .vault_pass

make run ENV=dev            # full loop in dev
make run ENV=prod           # full loop in prod (uses the Vault)
make diagnose-only ENV=dev  # deploy + diagnose only
make fix ENV=dev            # fix + verify only
make check ENV=dev          # --check (dry run)
make teardown ENV=dev       # delete the namespace
make lint                   # ansible-lint
```

`make run ENV=prod` needs the vault password:
`--vault-password-file .vault_pass` (already wired into the Makefile).

### Seeing it work

```
TASK [crashloop : Phase 1 | assert the failure is reproduced] ***
    "msg": "FAILURE REPRODUCED - webapp-684c54f8f5-zs2pm restarts=2 reason=Error exit=1"

TASK [crashloop : Phase 4 | assert recovery] ***
    "msg": "RECOVERED - 2/2 replicas ready in namespace tshoot-prod"
```

## What this practices in Ansible

- **roles**, `tasks/main.yml`, `defaults`, `handlers`, `notify`
- **Jinja2 templates** rendering Kubernetes manifests from variables
- **inventory + `group_vars`** and per-environment `vars_files`
- **Ansible Vault** for credentials, loaded conditionally
- **idempotent modules** (`kubernetes.core.k8s`, `k8s_info`) and `state: present/absent`
- **`register` + `until`/`retries`/`delay`** to wait for a condition
- **`assert`** to turn a runbook into an executable test
- **tags** (`--tags reproduce,diagnose`) and `--check`
- **ansible-lint** in CI

## A note on the lab

- The runner deliberately deletes and recreates the workload each run so the
  reproduction is deterministic — it is a *simulator*, not a converge-to-state
  play. It always ends in the healed state.
- `dev` needs no secret handling; `prod` demonstrates Vault.
- **No secret material is committed.** `vault/secrets.yml` and `.vault_pass` are
  gitignored; the repo ships only `vault/secrets.yml.example`. The vault password
  is distributed out-of-band — a secret manager, a CI secret, or `--ask-vault-pass`
  — never a file in the repo.
