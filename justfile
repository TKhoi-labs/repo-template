# repo-template — template-only tooling.
# Not rendered into generated repositories; the payload has its own justfile
# at template/justfile.jinja.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Render the module matrix and assert every generated repo.
test-template:
    scripts/test-template.sh

# Exercise the four-state health surface against its fixtures.
test-health:
    scripts/test-health.sh

# Run every check on the template itself.
test: test-template test-health

# Lint this template repo.
lint:
    yamllint copier.yml
    shellcheck scripts/test-template.sh scripts/test-health.sh

# Remove generated artifacts.
clean:
    rm -rf .build

# List the recipes in this file.
default:
    @just --list
