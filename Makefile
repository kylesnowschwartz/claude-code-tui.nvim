.SUFFIXES:

all: documentation lint luals test

# fixes style issues automatically
style-fix:
	stylua . -g '*.lua' -g '!deps/' -g '!nightly/'

# checks style without fixing (for CI)
style-check:
	stylua --check . -g '*.lua' -g '!deps/' -g '!nightly/'
	luacheck plugin/ lua/

# validates test structure before running (fail fast)
test-validate:
	@echo "🔍 Validating test structure..."
	@nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua if not dofile('scripts/validate_tests.lua') then vim.cmd('cquit 1') end" \
		-c "quit"

# runs all the test files.
test:
	make test-validate
	make deps
	nvim --version | head -n 1 && echo ''
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua MiniTest.run({ execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = 2 }) } })"

# runs all the test files on the nightly version, `bob` must be installed.
test-nightly:
	bob use nightly
	make test

# runs all the test files on the 0.8.3 version, `bob` must be installed.
test-0.8.3:
	bob use 0.8.3
	make test

# installs `mini.nvim`, used for both the tests and documentation.
# also installs nui.nvim (required for UI components) and nui-components for development.
deps:
	@mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim
	git clone --depth 1 https://github.com/MunifTanjim/nui.nvim deps/nui.nvim
	git clone --depth 1 https://github.com/grapp-dev/nui-components.nvim deps/nui-components.nvim

# installs deps before running tests, useful for the CI.
test-ci: deps test

# generates the documentation.
documentation:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua require('mini.doc').generate()" -c "qa!"

# installs deps before running the documentation generation, useful for the CI.
documentation-ci: deps documentation

# performs a lint check and fixes issue if possible, following the config in `stylua.toml`.
lint:
	stylua . -g '*.lua' -g '!deps/' -g '!nightly/'
	luacheck plugin/ lua/

luals-ci:
	rm -rf .ci/lua-ls/log
	.ci/lua-ls/bin/lua-language-server --configpath .luarc.json --logpath .ci/lua-ls/log --check .
	[ -f .ci/lua-ls/log/check.json ] && { cat .ci/lua-ls/log/check.json 2>/dev/null; exit 1; } || true

luals:
	mkdir -p .ci/lua-ls
	curl -sL "https://github.com/LuaLS/lua-language-server/releases/download/3.7.4/lua-language-server-3.7.4-darwin-x64.tar.gz" | tar xzf - -C "${PWD}/.ci/lua-ls"
	make luals-ci

# setup
setup:
	./scripts/setup.sh
