SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help setup build run-local deploy cleanup validate ci

help:
	@echo "SRE Course Repository Targets"
	@echo ""
	@echo "  make setup      # check prerequisites and mark scripts executable"
	@echo "  make build      # generate repository module index artifact"
	@echo "  make run-local  # create local kind cluster and deploy monitoring stack"
	@echo "  make deploy     # deploy monitoring stack to current kubectl context"
	@echo "  make cleanup    # remove stack from cluster"
	@echo "  make validate   # validate links, structure, and shell scripts"
	@echo "  make ci         # CI entrypoint"

setup:
	@chmod +x scripts/*.sh 05-gcp-operations/scripts/*.sh 06-linux-networking/scripts/*.sh
	@bash scripts/bootstrap-lab.sh

build:
	@bash scripts/build-course-index.sh

run-local:
	@bash scripts/run-local-lab.sh

deploy:
	@bash scripts/deploy-monitoring-stack.sh

cleanup:
	@bash scripts/cleanup-lab.sh --yes

validate:
	@bash scripts/validate-repo.sh

ci: build validate

