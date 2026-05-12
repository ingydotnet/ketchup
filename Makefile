R := https://github.com/makeplus/makes
M := .cache/makes
$(shell [ -d '$M' ] || git clone -q $R '$M')

CLAUDE-MODE := full

include $M/init.mk
include $M/claude.mk
include $M/gh.mk
include $M/jq.mk
include $M/clean.mk
include $M/shell.mk

ANTHROPIC-TOKEN-FILE := $(HOME)/.anthropic-api-token
GH-TOKEN-FILE := $(HOME)/.github-tokens/ketchup

KETCHUP-DEPS := $(CLAUDE-READY) $(JQ)

ifndef GITHUB_ACTIONS
KETCHUP-DEPS += $(GH-TOKEN-FILE)
ketchup: export GITHUB_TOKEN = $(shell cat $(GH-TOKEN-FILE))
# Without this, claude defaults to ~/.claude (not granted by the pkio sandbox) and hangs silently.
ketchup: export CLAUDE_CONFIG_DIR = $(HOME)/.config/pkio/cache/claude
endif

ketchup: $(KETCHUP-DEPS)
	stdbuf -oL -eL $(CLAUDE) $(CLAUDE-ALLOWED-TOOLS) --verbose --output-format stream-json \
	  -p < .claude/skills/ketchup/SKILL.md \
	  | stdbuf -oL $(JQ) --unbuffered -Rrf util/stream.jq

$(ANTHROPIC-TOKEN-FILE):
	@echo 'Error: Anthropic API key not found at $@'
	@echo 'Create one at https://console.anthropic.com/settings/keys'
	@echo 'and save it to $@'
	@exit 1

$(GH-TOKEN-FILE):
	@echo 'Error: GitHub token not found at $@'
	@echo 'Create a fine-grained PAT at'
	@echo 'https://github.com/settings/personal-access-tokens/new'
	@echo 'and save it to $@'
	@exit 1

publish-secrets: $(GH) $(ANTHROPIC-TOKEN-FILE) $(GH-TOKEN-FILE)
	gh secret set ANTHROPIC_API_KEY -R ingydotnet/ketchup < $(ANTHROPIC-TOKEN-FILE)
	gh secret set KETCHUP_TOKEN -R ingydotnet/ketchup < $(GH-TOKEN-FILE)

claude: claude-nono
