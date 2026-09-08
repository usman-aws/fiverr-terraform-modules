# Contributing

## Adding a new module

1. Create `modules/<name>/` with, at minimum, `main.tf`, `outputs.tf`, a
   `versions.tf` or `providers.tf` with `required_version`/`required_providers`,
   and a `README.md` following the structure used by [`modules/vpc`](modules/vpc/README.md)
   (Overview, Architecture, Features, Resources Created, Configuration, Usage,
   Outputs, Security Considerations, Cost Considerations, Limitations).
2. Add a runnable example under `examples/<name>-basic/` that calls the module
   with `source = "../../modules/<name>"`.
3. Add a row for the module to the table in the root [`README.md`](README.md).
4. Open a PR. CI (`.github/workflows/terraform.yml`) auto-discovers any
   directory containing `.tf` files, so a new module or example is formatted,
   linted, and validated without touching the workflow file.

## Local checks before opening a PR

```bash
terraform fmt -check -recursive -diff
cd modules/<name>   # or examples/<name>
terraform init -backend=false
terraform validate
```

## Conventions

- Modules read configuration from a `vars.yaml` file (see `modules/vpc`) rather
  than exposing many `variables.tf` inputs, to keep example diffs small and
  `terraform plan` output easy to reason about. Follow the same pattern for
  consistency unless a module has a strong reason not to.
- Do not add a `provider "aws" {}` block inside a module — only `examples/`
  and standalone root configurations configure providers. See
  [`modules/vpc/providers.tf`](modules/vpc/providers.tf) for why.
- Tag every resource with the module's merged `local.tags`, not a bare
  `{ Name = ... }` map, so caller-supplied tags (`vars.yaml`'s `tags` key)
  actually reach AWS.

## Releasing

Tag a commit on `main` with a semantic version (`vX.Y.Z`) once a module change
is ready to be consumed externally via a `?ref=` pinned source. Bump the major
version on any breaking change to a module's `vars.yaml` schema or outputs.
