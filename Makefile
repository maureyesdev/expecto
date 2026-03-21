PLENARY_DIR ?= /tmp/plenary.nvim
NVIM        ?= nvim

.PHONY: test-setup test clean

test-setup:
	@if [ ! -d "$(PLENARY_DIR)" ]; then \
		echo "Cloning plenary.nvim..."; \
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR); \
	else \
		echo "plenary.nvim already present at $(PLENARY_DIR)"; \
	fi

test:
	$(NVIM) --headless \
		-u NONE \
		-c "set rtp+=$(PLENARY_DIR)" \
		-c "set rtp+=." \
		-c "runtime! plugin/plenary.vim" \
		-c "lua require('plenary.test_harness').test_directory('tests/unit', { minimal_init = 'tests/minimal_init.lua', sequential = true })" \
		-c "qa!"

clean:
	@echo "Nothing to clean."
