# Azure Naming & Tagging Convention — Portfolio-Wide Standard

Pattern: `<resource-type-abbreviation>-<project-slug>-<environment>`

When the project slug already begins with the resource-type abbreviation (e.g.
slug `nsg-scanner` with abbreviation `nsg`), do not repeat the token — the name
is `nsg-scanner-<env>`, not `nsg-nsg-scanner-<env>`.

## Project slug for this repo

Repo is `terraform-storage-baseline`; the slug used inside resource names and
tags is **`storage-baseline`**. The `terraform-` prefix is dropped the same way
every sibling drops its tool/platform prefix (`azure-cost-sentinel` tags
`cost-sentinel`, `landing-zone-foundation` tags `landing-zone`) — the prefix
names the *tool*, not the workload, and Azure resource names should describe
the workload.

## Resource type abbreviations (CAF standard)

`rg` (resource group), `st` (storage account, no hyphens allowed), `plan` (App
Service plan), `func` (Function App), `aa` (Automation Account), `log` (Log
Analytics), `appi` (App Insights), `ag` (Action Group), `budget` (Budget).

## Environment

`dev` for all current portfolio projects.

## Region

`eastus2`, matching every sibling project's deployed resources.

## Storage account caveat — the binding constraint for THIS project

Lowercase alphanumeric only, 3-24 chars, no hyphens, globally unique.

Naively concatenating gives `st` + `storagebaseline` + `dev` = `ststoragebaselinedev`
(20 chars), leaving only 4 characters for a uniqueness suffix and stuttering
`st`/`storage` — the exact repetition the no-repeat rule above exists to
prevent. So the `storage` token is dropped from storage account names only:

```
stbaselinedev<suffix>     13 chars + 6-char suffix = 19 chars
```

The resource group keeps the full slug (`rg-storage-baseline-dev`) — it has no
length ceiling and no stutter, since `rg` is not a prefix of `storage`.

**This applies to the example root module.** The reusable module itself takes
the account name as an input and hardcodes nothing — that is the point of a
module.

## Tagging (apply to resource group + any non-inheriting resource)

```
portfolio: azure-devops-portfolio
project: storage-baseline
environment: dev
```

## Terraform-specific identifier hazard — read before the first commit

Terraform leaks identifiers in places Bicep does not. All three are gitignored:

- **`*.tfstate` / `*.tfstate.backup`** — plaintext JSON containing the full
  subscription ID, every resource ID, and, for a storage account, the **primary
  and secondary access keys**. Bicep has no equivalent artifact. State is never
  committed.
- **`*.tfvars`** — carries `subscription_id` for the azurerm provider.
  `terraform.tfvars.example` is committed with placeholders; the real file is not.
- **`.terraform/`** — provider binaries and a `terraform.tfstate` backend stub.

`.terraform.lock.hcl` **is** committed — it pins provider hashes and carries no
identifiers.

## Documentation placeholders (use in every committed file — never the real value)

```
tenant ID          -> <TENANT_ID>          example GUID: aaaaaaaa-0000-1111-2222-bbbbbbbbbbbb
subscription ID    -> <SUBSCRIPTION_ID>    example GUID: 11111111-0000-2222-3333-444444444444
principal/object ID (managed identity, SP, user) -> <PRINCIPAL_ID>
app/client ID      -> <CLIENT_ID>
resource ID path   -> /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG_NAME>/...
storage access key -> <STORAGE_KEY>
tenant domain      -> contoso.onmicrosoft.com
owner/user email   -> user@contoso.com
billing account / enrollment ID -> <BILLING_ACCOUNT_ID>
```

Resource names built from the pattern above (`rg-storage-baseline-dev`) carry no
secret and may be shown as-is. Redact the uniqueness suffix only where it sits
next to a subscription ID.
