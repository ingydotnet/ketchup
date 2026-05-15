M := ../.cache/makes
$(shell [ -d '$M' ] || git clone -q https://github.com/makeplus/makes '$M')

include $M/init.mk
include $M/clean.mk
PYTHON-VENV := $(ROOT)/venv
include $M/python.mk
SHELL-DEPS += $(PYTHON-VENV)
include $M/shell.mk

export UV_LINK_MODE := copy
export NO_MKDOCS_2_WARNING := 1

# Override python.mk's venv recipe (matches gloat/www/Makefile pattern):
# use uv venv to avoid an ensurepip hang with uv-managed standalone Python.
$(PYTHON-VENV): $(PYTHON)
	@echo '+++ Installing a Python virtualenv in $@'
	uv venv --python $(PYTHON-NAME) $@
	$(if $(wildcard requirements.txt),uv pip install -r requirements.txt,true)
	@echo

REPO ?= git@github.com:ingydotnet/ketchup

MAKES-CLEAN := site docs/reports docs/dates.json
MAKES-REALCLEAN := $(PYTHON-VENV)

DEPS := $(PYTHON-VENV)

default:: build

serve: $(DEPS)
	mkdocs serve --livereload --watch ../report

build: $(DEPS)
	mkdocs build -d site

site: build

publish: site
	cd $< && \
	  git init -q && \
	  git add -A && \
	  git commit -q -m 'Deploy to gh-pages' && \
	  git push -f $(REPO) HEAD:gh-pages
	$(RM) -r site
