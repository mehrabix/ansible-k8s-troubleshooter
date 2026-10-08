SHELL := /bin/bash
ENV      ?= dev
SCENARIO ?= crashloop
VAULT    ?= .vault_pass

.PHONY: help
help:            ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: run
run:             ## Run the scenario (ENV=dev|prod)
	ansible-playbook playbooks/run-scenario.yml -e env=$(ENV) -e scenario=$(SCENARIO) --vault-password-file $(VAULT)

.PHONY: check
check:           ## Dry run (--check) of the scenario
	ansible-playbook playbooks/run-scenario.yml -e env=$(ENV) -e scenario=$(SCENARIO) --vault-password-file $(VAULT) --check

.PHONY: diagnose-only
diagnose-only:   ## Run only the deploy + diagnose phases
	ansible-playbook playbooks/run-scenario.yml -e env=$(ENV) -e scenario=$(SCENARIO) --vault-password-file $(VAULT) --tags reproduce,diagnose

.PHONY: fix
fix:             ## Run only the fix + verify phases
	ansible-playbook playbooks/run-scenario.yml -e env=$(ENV) -e scenario=$(SCENARIO) --vault-password-file $(VAULT) --tags fix,verify

.PHONY: teardown
teardown:        ## Delete the scenario namespace (ENV=dev|prod)
	ansible-playbook playbooks/teardown.yml -e env=$(ENV)

.PHONY: lint
lint:            ## ansible-lint
	ansible-lint

.PHONY: syntax
syntax:          ## ansible-playbook --syntax-check
	ansible-playbook playbooks/run-scenario.yml --syntax-check

.PHONY: vault-edit
vault-edit:      ## Edit the encrypted secrets with Ansible Vault
	ansible-vault edit vault/secrets.yml --vault-password-file $(VAULT)
