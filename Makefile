.DEFAULT_GOAL := help

PNPM_VERSION := 12.16.1

.PHONY: setup install-node-deps
setup: install-node-deps install-skill-node-deps ## Install development dependencies (repository and skill Node.js deps)

install-node-deps: ## Install repository-level Node.js dependencies (needed by make lint)
	@if command -v pnpm >/dev/null 2>&1; then \
		pnpm install --frozen-lockfile; \
	elif command -v npx >/dev/null 2>&1; then \
		npx --yes pnpm@$(PNPM_VERSION) install --frozen-lockfile; \
	else \
		echo "pnpm または npx が必要です" >&2; \
		exit 1; \
	fi

.PHONY: install-skill-node-deps
install-skill-node-deps: ## Install Node.js dependencies of skills that commit a lockfile (needed by make test)
	@if command -v pnpm >/dev/null 2>&1; then \
		pnpm=pnpm; \
	elif command -v npx >/dev/null 2>&1; then \
		pnpm="npx --yes pnpm@$(PNPM_VERSION)"; \
	else \
		echo "pnpm または npx が必要です" >&2; \
		exit 1; \
	fi; \
	for d in skills/*/scripts skills/*/*/scripts; do \
		[ -f "$$d/pnpm-lock.yaml" ] || continue; \
		echo "==> $$d"; \
		$$pnpm install --frozen-lockfile --ignore-workspace --dir "$$d" || exit 1; \
	done

.PHONY: lint
lint: ## Run linters in parallel (JOBS=N to set concurrency): shellcheck, frontmatter, license, shared partials, script invocation, AGENTS.md size, markdown punctuation, skill test placement, Node.js syntax
	@node ./bin/run-lints.mjs

.PHONY: test
test: ## Run unit tests in parallel (SKILLS="a b" to filter by skill, JOBS=N to set concurrency)
	@node ./bin/run-tests.mjs $(if $(SKILLS),--skills "$(SKILLS)") $(if $(JOBS),--jobs "$(JOBS)")

.PHONY: validate
validate: ## Validate skills against the gh skill spec (dry run)
	gh skill publish --dry-run

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'
