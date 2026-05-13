# Contributing

Contributions are welcome.

## Local Workflow

Install the local Git hooks first:

```bash
make hooks
```

Run the same checks manually when needed:

```bash
make validate
make lint
```

The hooks run `terraform fmt`, initialize each module with `-backend=false`,
validate module syntax and providers, run TFLint, and check YAML formatting.
Install tools with Homebrew where possible.

## Module Guidelines

- Keep modules generic. Do not hardcode personal domains, emails, OCIDs, regions, or IP addresses.
- Prefer explicit variables and validations over hidden assumptions.
- Add outputs for IDs, names, endpoints, and values required by downstream modules.
- Keep Always Free limits documented in variables and examples.
- Mark paid or potentially paid resources as opt-in.

## Pull Requests

Include:

- Purpose and scope.
- Modules changed.
- Validation commands run.
- Any cost impact or new OCI service dependency.
