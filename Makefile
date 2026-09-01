.DEFAULT_GOAL := help

.PHONY: lint
lint: ## Run linters (shellcheck, frontmatter, license, HOW_TO_USE, script invocation, AGENTS.md size, markdown punctuation)
	@find bin -name '*.sh' -type f -exec shellcheck {} +
	@find skills -name '*.sh' -type f -exec shellcheck {} + 2>/dev/null || true
	sh ./bin/lint-frontmatter.sh
	sh ./bin/lint-license.sh
	sh ./bin/lint-how-to-use.sh
	sh ./bin/lint-script-invocation.sh
	sh ./bin/lint-agents-md-size.sh
	sh ./bin/lint-markdown-punctuation.sh

.PHONY: test
test: ## Run unit tests for lint scripts
	@failed=0; \
	for t in bin/tests/test-*.sh; do \
		echo "==> $$t"; \
		bash "$$t" || failed=1; \
	done; \
	[ $$failed -eq 0 ]

.PHONY: validate
validate: ## Validate skills against the gh skill spec (dry run)
	gh skill publish --dry-run

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
