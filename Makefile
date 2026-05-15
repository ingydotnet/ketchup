R := https://github.com/makeplus/makes
M := .cache/makes
$(shell [ -d '$M' ] || git clone -q $R '$M')

CLAUDE-MODE := full

include $M/init.mk
include $M/claude.mk
include $M/gh.mk
include $M/jq.mk
include $M/shellcheck.mk
include $M/ys.mk
include $M/shell.mk
include $M/clean.mk

MAKES-CLEAN := \
  www/docs/dates.json \
  www/docs/reports/ \

MAKES-REALCLEAN := \
  www/hooks/__pycache__/ \
  www/venv/ \


GH-TOKEN-FILE := $(HOME)/.github-tokens/ketchup
CLAUDE-CREDS-FILE := $(or $(CLAUDE_CONFIG_DIR),$(HOME)/.claude)/.credentials.json
KETCHUP-MODEL = $(shell $(YS) -Y ketchup.yaml -e '.get("default model")')
SYSTEMD-USER-DIR := $(HOME)/.config/systemd/user

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
	@test -s $(CLAUDE-CREDS-FILE) || { \
	  echo 'Error: $(CLAUDE-CREDS-FILE) is empty.' >&2; \
	  echo 'Run via pkio (so CLAUDE_CONFIG_DIR points at the real creds dir).' >&2; \
	  exit 1; }
	gh secret set CLAUDE_CREDENTIALS < $(CLAUDE-CREDS-FILE)
	gh secret set KETCHUP_TOKEN < $(GH-TOKEN-FILE)

run-gha: $(GH) publish-secrets
	gh workflow run ketchup.yaml

install-rsync:
	@test -n "$(RELAY)" || { \
	  echo 'Set RELAY=<ssh-alias for your relay host>' >&2; exit 1; }
	mkdir -p $(SYSTEMD-USER-DIR)
	sed -e 's|@CREDS_DIR@|$(patsubst %/,%,$(dir $(CLAUDE-CREDS-FILE)))|g' \
	    etc/systemd/ketchup-rsync.path.in \
	    > $(SYSTEMD-USER-DIR)/ketchup-rsync.path
	sed -e 's|@CREDS_FILE@|$(CLAUDE-CREDS-FILE)|g' \
	    -e 's|@RELAY_HOST@|$(RELAY)|g' \
	    etc/systemd/ketchup-rsync.service.in \
	    > $(SYSTEMD-USER-DIR)/ketchup-rsync.service
	systemctl --user daemon-reload
	systemctl --user enable --now ketchup-rsync.path
	systemctl --user restart ketchup-rsync.path

claude: claude-nono

serve-www:
	$(MAKE) -C www serve

publish-www:
	$(MAKE) -C www publish
