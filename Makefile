SHELL := /bin/bash

.PHONY: fmt validate lint hooks

fmt:
	terraform fmt -recursive

validate:
	./scripts/validate.sh

lint:
	./scripts/lint.sh
	yamllint .

hooks:
	./scripts/install-hooks.sh
