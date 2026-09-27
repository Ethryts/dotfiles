.PHONY: test

NVIM ?= nvim
TESTS := tests/config_spec.lua tests/storage_spec.lua tests/anchor_spec.lua tests/git_spec.lua tests/editor_spec.lua tests/clipboard_spec.lua tests/root_spec.lua tests/reliability_spec.lua tests/relocation_spec.lua tests/quickfix_spec.lua tests/workflow_spec.lua tests/run.lua

test:
	@set -e; for test in $(TESTS); do \
		printf '==> %s\n' "$$test"; \
		NVIM_LOG_FILE=/tmp/review-comments-nvim-test.log \
		XDG_STATE_HOME=/tmp/review-comments-nvim-state \
		XDG_DATA_HOME=/tmp/review-comments-nvim-data \
		$(NVIM) --headless -u tests/minimal_init.lua -l "$$test"; \
	done
