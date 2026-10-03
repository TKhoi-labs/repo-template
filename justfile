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

# Matrix-level properties: bundles, ownership disjointness, action pinning,
# answer migration, and `copier update --defaults` being a no-op everywhere.
test-matrix:
    scripts/test-matrix.sh

# Lint the rendered workflows with actionlint and zizmor, when available.
test-workflows:
    scripts/test-workflows.sh

# Run every check on the template itself.
test: test-template test-health test-matrix test-workflows

# Lint this template repo.
lint:
    yamllint copier.yml
    shellcheck scripts/test-template.sh scripts/test-health.sh scripts/test-matrix.sh scripts/test-workflows.sh scripts/lib/template-snapshot.sh

# Remove generated artifacts.
clean:
    rm -rf .build

# List the recipes in this file.
default:
    @just --list
