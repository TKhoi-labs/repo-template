# repo-template — template-only tooling.
# Not rendered into generated repositories; the payload has its own justfile
# at template/justfile.jinja.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Render the module matrix and assert every generated repo.
test-template:
    scripts/test-template.sh

# Lint this template repo (requires yamllint and shellcheck).
lint:
    yamllint copier.yml
    shellcheck scripts/test-template.sh

# Remove generated artifacts.
clean:
    rm -rf .build

# List the recipes in this file.
default:
    @just --list
