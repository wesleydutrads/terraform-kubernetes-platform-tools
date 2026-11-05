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

O hook de validação e make validate executam scripts/validate.sh. Por padrão,
o script valida os módulos já inicializados sem executar init; dependências
ausentes produzem falha. TF_BIN seleciona um Terraform existente e verificado.
Os caminhos dos módulos são ancorados neste checkout, não no diretório corrente.
Todos os diretórios diretamente abaixo de modules são incluídos.

scripts/validate.sh --init permite inicialização explícita com -backend=false e
-input=false antes de validar cada módulo. Essa opção preserva o fluxo anterior,
mas pode acessar registros, baixar providers e módulos e escrever arquivos locais;
não é uma opção offline. Revise executável, lockfiles e dependências antes de usar.
Não há instalação de Terraform, upgrade automático ou acesso ao backend por init.
Outros hooks continuam executando formatação Terraform, TFLint e lint de YAML.

Execute o teste de contrato deste checkout, sem depender de repositórios irmãos:
python3 -B tests/test_validate_local.py -v
O teste copia somente os wrappers para uma árvore sintética temporária e usa CLI
falsa, ambiente mínimo e timeout por chamada; não executa Terraform real nem
comprova validade HCL, providers ou ambiente cloud. Inclui árvore vazia, caminhos
com espaços e propagação de falha de validate após init simulado bem-sucedido.

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
