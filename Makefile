R := https://github.com/makeplus/makes
M := .cache/makes
$(shell [ -d '$M' ] || git clone -q $R '$M')

CLAUDE-MODE := full

include $M/init.mk
include $M/claude.mk
include $M/gh.mk
include $M/jq.mk
include $M/clean.mk
include $M/ys.mk
include $M/shell.mk

GH-TOKEN-FILE := $(HOME)/.github-tokens/ketchup
CLAUDE-CREDS-FILE := $(or $(CLAUDE_CONFIG_DIR),$(HOME)/.claude)/.credentials.json
KETCHUP-MODEL = $(shell $(YS) -Y ketchup.yaml -e '.get("default model")')

KETCHUP-DEPS := $(CLAUDE-READY) $(JQ) $(YS)

ifndef GITHUB_ACTIONS
KETCHUP-DEPS += $(GH-TOKEN-FILE)
ketchup: export GITHUB_TOKEN = $(shell cat $(GH-TOKEN-FILE))
endif

ketchup: $(KETCHUP-DEPS)
	stdbuf -oL -eL \
	  $(CLAUDE) $(CLAUDE-ALLOWED-TOOLS) \
	    --model $(KETCHUP-MODEL) \
	    --verbose \
	    --output-format stream-json \
	    -p < .claude/skills/ketchup/SKILL.md \
	| stdbuf -oL $(JQ) --unbuffered -Rrf util/stream.jq

$(GH-TOKEN-FILE):
	@echo 'Error: GitHub token not found at $@'
	@echo 'Create a fine-grained PAT at'
	@echo 'https://github.com/settings/personal-access-tokens/new'
	@echo 'and save it to $@'
	@exit 1

publish-secrets: $(GH) $(CLAUDE-CREDS-FILE) $(GH-TOKEN-FILE)
	gh secret set CLAUDE_CREDENTIALS -R ingydotnet/ketchup < $(CLAUDE-CREDS-FILE)
	gh secret set KETCHUP_TOKEN -R ingydotnet/ketchup < $(GH-TOKEN-FILE)

run-gha: $(GH) publish-secrets
	gh workflow run ketchup.yaml -R ingydotnet/ketchup

claude: claude-nono
