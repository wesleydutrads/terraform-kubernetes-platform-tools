# Contributing

Contributions are welcome.

## Local Workflow

Run checks before opening a pull request:

```bash
terraform fmt -recursive -check
```

If a module has examples, initialize and validate from the example directory:

```bash
terraform init
terraform validate
```

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
