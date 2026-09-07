# Terraform Storage Baseline

> A reusable, versioned Terraform module for a secure-by-default Azure
> storage account, plus an example root module that consumes it — the
> portfolio's first non-Bicep IaC project.

![Azure](https://img.shields.io/badge/Azure-Storage-0078D4)
![Terraform](https://img.shields.io/badge/Terraform-1.16-844FBA)
![Provider](https://img.shields.io/badge/azurerm-4.81-844FBA)
![Cost](https://img.shields.io/badge/cost-~%240%2Fmo-success)

## The problem

An Azure storage account created with defaults is not secure. Anonymous blob
access is permitted, the TLS floor sits below current guidance, account keys
work as a shared credential that never expires and cannot be attributed to a
person, the firewall accepts traffic from anywhere, and neither versioning nor
soft delete is on.

Every one of those is a separate setting on a separate part of the resource. A
person creating one account can work through a checklist. A team creating
thirty cannot, and reviewing thirty accounts to find the one where a checklist
step was missed is not a job anyone does reliably.

A module makes the secure configuration the path of least resistance: the
default *is* the baseline, and departing from it is an explicit, reviewable
line in someone's Terraform.

## What it does

- **`modules/secure-storage`** — a storage account with HTTPS-only transport, a
  TLS 1.2 floor, anonymous blob access disabled, shared access keys disabled,
  double encryption at rest, blob versioning with 7-day soft delete for blobs
  and containers, a firewall that denies by default, and a lifecycle policy —
  all from three required inputs.
- **A deliberately tiered input surface.** Two controls are fixed with no
  variable at all, several are variables whose validation refuses an insecure
  value, and the rest are free. See below.
- **`examples/complete`** — a root module that consumes it, creates the
  resource group and containers, and grants the caller the data-plane role the
  module's own defaults make necessary.
- **22 `terraform test` assertions** proving the baseline holds, that insecure
  input is refused, and that documented opt-outs work without relaxing anything
  else.
- **Validation-only CI** — `fmt`, `validate`, `terraform test`, `tflint` and
  Checkov, with no Azure credential and no apply job.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for the module call graph
and resource boundary.

The module owns three resources: the storage account, its containers, and its
lifecycle management policy. It deliberately does not create the resource
group, and declares no `provider` block — both belong to the root module, so
the same module serves callers with different subscriptions, provider
configurations or resource group strategies.

**Services used:** Azure Storage (StorageV2) · Azure RBAC · Terraform
(`hashicorp/azurerm` 4.x).

**Auth:** the operator authenticates with the Azure CLI (`az login`). There is
no service principal, no client secret and no OIDC federation — `terraform
apply` is a workstation operation, consistent with this portfolio's standing
decision not to hold a federated deploy identity for a public repository. The
one role assignment the example creates is `Storage Blob Data Contributor`,
scoped to the single storage account rather than the resource group.

## Three tiers of control

A module that exposes every provider setting is a thin wrapper that guarantees
nothing. A module that exposes nothing cannot be reused. The opinion lives in
which settings are which.

**Tier A — fixed. No variable exists.** `https_traffic_only_enabled = true`,
`allow_nested_items_to_be_public = false`, and containers are always private.
There is no legitimate reason to want a secure-by-default storage baseline that
serves plaintext HTTP or anonymous blobs; overriding these would mean wanting a
different module.

**Tier B — a variable, validated to refuse an insecure value.**
`min_tls_version` exists so the floor can be raised, never lowered. Account
kinds that cannot support versioning or soft delete are refused. Retention
windows are range-checked, and container names are checked against Azure's
actual naming rules rather than failing at apply time.

**Tier C — genuinely free.** Name, resource group, location, tags, containers,
lifecycle rules, network allowlists, replication choice.

## Two decisions worth explaining

**Account keys are disabled by default.** This is the setting that makes the
module a security baseline rather than a naming convention, and it has a
consequence: the account is unusable on creation until a principal is granted a
data-plane role. That is the intended failure mode — access is granted
deliberately rather than inherited by whoever can manage the resource.

It also puts a genuinely confusing distinction front and centre. A
**control-plane** role (`Owner`, `Contributor`, `Storage Account Contributor`)
authorises managing the account *resource* and grants nothing at all on the
*blobs inside it*. Reading a blob needs a **data-plane** role such as `Storage
Blob Data Reader`. Holding one implies nothing about the other, and conflating
them produces a 403 against a token that looks entirely valid — a bug that cost
a sibling project in this portfolio a full checkpoint.

**Blob versioning ships with a lifecycle policy, because it has to.**
Versioning is a data-protection win and an unbounded cost-growth bug in equal
measure: every overwrite retains a billable previous version indefinitely and
nothing cleans them up. The default policy tiers base blobs to cool at 30 days
and archive at 90 and **never deletes them**, while pruning previous versions
and snapshots at 90 days. Live data is only ever moved to cheaper storage.

## Environment

Developed and validated against the live Azure subscription behind this
portfolio, in `eastus2`, alongside the other projects in the series — not a
disposable sandbox. Validation is an apply/destroy cycle; no resource is left
standing.

## What this doesn't do

- **Not a general-purpose storage module.** It is narrowly scoped to the
  secure-by-default baseline. Object replication, SFTP, NFSv3 and static
  website hosting are all out of scope.
- **Not network-private.** The firewall denies by default, which is a
  meaningful control, but the endpoint is still a public one with an allowlist.
  Genuine isolation needs Private Link, which adds roughly $7/month per
  endpoint plus a VNet, a subnet and a Private DNS zone that a standalone
  module has no business requiring. The README says *firewall-restricted*, and
  means it.
- **No customer-managed keys.** The module exposes a system-assigned identity
  so CMK is possible downstream; it is not wired up here.
- **No remote state backend.** State is local. A remote backend needs a storage
  account to hold the state, which is the thing this module creates —
  bootstrapping that is a different project, and half-building it would be
  worse than documenting it.
- **No apply pipeline.** CI validates and never deploys.

## Running it yourself

Requires Terraform >= 1.9 and an authenticated Azure CLI.

```bash
az login
cd examples/complete
cp terraform.tfvars.example terraform.tfvars   # then edit it

export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform init
terraform plan
terraform apply
```

Two things will bite you if you skip them:

- **Set `allowed_ip_ranges` to your own public egress address**
  (`curl -s https://api.ipify.org`). The module denies by default, so leaving
  it empty means nothing reaches the blob data plane — including you. Azure
  rejects RFC1918 ranges and `/31` and `/32` prefixes here; pass a bare
  address.
- **Creating the role assignment needs `Owner` or `User Access Administrator`**
  at the scope. With only `Contributor`, set `assign_data_plane_role = false`
  or the apply fails on the assignment rather than on the storage account.

Tear down with `terraform destroy`.

### Consuming the module from your own root module

```hcl
module "storage" {
  source = "github.com/realitylvn/terraform-storage-baseline//modules/secure-storage?ref=v1.0.0"

  name                = "stexampledev01"
  resource_group_name = azurerm_resource_group.this.name
  location            = "eastus2"
  allowed_ip_ranges   = ["203.0.113.10"]
}
```

Pin `ref` to a release tag. `main` is not a version.

## Sample output

`terraform apply` on the example, against a real subscription:

```
module.storage.azurerm_storage_account.this: Creation complete after 2m11s
azurerm_role_assignment.caller_blob_data[0]: Creating...
module.storage.azurerm_storage_container.this["artifacts"]: Creation complete after 12s
module.storage.azurerm_storage_container.this["logs"]: Creation complete after 12s
module.storage.azurerm_storage_management_policy.this[0]: Creation complete after 1s
azurerm_role_assignment.caller_blob_data[0]: Creation complete after 26s

Apply complete! Resources: 5 added, 0 changed, 1 destroyed.

security_posture = {
  "allow_nested_items_to_be_public" = false
  "blob_versioning_enabled"         = true
  "https_traffic_only_enabled"      = true
  "infrastructure_encryption_enabled" = true
  "lifecycle_policy_applied"        = true
  "min_tls_version"                 = "TLS1_2"
  "network_default_action"          = "Deny"
  "public_network_access_enabled"   = true
  "shared_access_key_enabled"       = false
}
```

Confirmed against Azure afterwards, rather than by reading Terraform state:

```
$ az rest --method get --url ".../stbaselinedev<suffix>?api-version=2023-05-01" \
    --query "properties.{...}"
{ "httpsOnly": true, "infraEncryption": true, "minTls": "TLS1_2",
  "netDefault": "Deny", "publicBlob": false, "sharedKey": false }
```

Being configured and being enforced are different claims, so each control was
tested rather than assumed:

| Test | Result |
|---|---|
| Entra ID auth from the allowed IP | succeeds — lists `artifacts`, `logs` |
| Anonymous HTTPS container listing | `409 PublicAccessNotPermitted` |
| Plaintext HTTP | `400 AccountRequiresHttps` |
| Shared-key auth on the data plane | `KeyBasedAuthenticationNotPermitted` |

One nuance that is easy to state wrongly. `allowSharedKeyAccess = false` does
not delete, rotate or hide the account keys — `az storage account keys list`
still returns them to anyone with `listkeys` on the control plane. What changes
is that the **data plane refuses them**. The key is retrievable and useless.
The accurate claim is "shared key authentication is refused", not "the account
has no keys".

## Cost

**Measured, not estimated: under one cent for the full validation cycle.**

The account lived about 12 minutes and recorded **37 transactions and 0 GB
stored**. At eastus2 Standard Hot LRS retail rates (Azure Retail Prices API,
2026-09-07) — $0.0184/GB/month stored, $0.065 per 10K write operations — that
is roughly **$0.0002**, with storage itself at $0.00 because nothing was
written.

Billed cost data lags 8–24 hours, so this is computed from measured usage
against published rates rather than read off an invoice.

Design estimate: **~$0.00/month.** An empty StorageV2 LRS account carries no
hourly meter — storage billing is per-GB-stored and per-transaction, and this
account holds no data. Validation is an apply/destroy cycle rather than a
standing resource, and the default lifecycle policy exists specifically so that
versioning cannot grow the bill without bound.

## Tests

```bash
cd modules/secure-storage
terraform test
```

22 assertions across three files: `defaults.tftest.hcl` (the secure defaults
hold with minimal input), `validation.tftest.hcl` (insecure input is refused),
`overrides.tftest.hcl` (documented opt-outs work and stay scoped). All run at
`command = plan` — nothing is created.

The tests use `mock_provider`, and the reason is worth stating because it was a
wrong assumption caught by checking. The azurerm provider acquires an access
token when it is *configured*, not when a resource is planned, so a real
provider block makes even plan-only tests require a live Azure credential. That
would mean giving CI a credential this repository deliberately does not have.
Mocking removes the provider entirely.

The trade is that mocked tests assert this module's configuration logic, not
the provider's behaviour, so they cannot catch a value the provider would
reject. Provider acceptance is proved separately by `terraform plan` against a
real subscription — a workstation step. Each layer covers the other's blind
spot.

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) runs
`terraform fmt -check`, `terraform validate` on both the module and the
example, the `terraform test` suite, `tflint` with the azurerm ruleset, and
Checkov against CIS storage benchmarks.

Checkov is there so the module is not the only thing asserting the module is
secure — an independent benchmark maintained by people with no stake in this
repository is a different kind of evidence than a test written by its author.

It earned that place. Its first run reported **12 passed, 9 failed**, and two
of those failures were real: `CKV_AZURE_35` and `CKV_AZURE_36` flagged an
account that had *demonstrably* been created with a default-Deny firewall and
the trusted-services bypass. The control was applied; Checkov could not see it,
because it lived inside a `dynamic "network_rules"` block and static analysis
cannot evaluate one. That block existed only to avoid a cosmetic no-op plan
diff, and it had already made a control unassertable in a test. Hiding the
network control from a scanner is a bad trade for a tidier diff, so the block
is now static and always emitted.

The current run is **14 passed, 0 failed, 7 skipped**. The seven are declared
as inline `checkov:skip=<ID>:<reason>` comments, not suppressed in
configuration, so they appear in the report as *skipped with a stated reason*
rather than disappearing: five are the documented design decisions above
(reachable endpoint behind a Deny firewall, LRS default, no CMK, no private
endpoint, no queue service) and two are a real gap scoped out on purpose — blob
read logging needs a Log Analytics workspace this module has no business
requiring.

A green scan that quietly hides seven disagreements would be worse than a red
one.

There is no apply job and no Azure credential in CI, by the same standing
decision described under **Auth**.

## Built with

Designed and reviewed with Claude (architecture, spec-tightening, this
README), implemented with Claude Code and the Terraform CLI in VS Code.
[`REVIEW.md`](REVIEW.md) is the running build log — including the three test
failures and one wrong CI assumption that shaped the final design.

---

## Portfolio series

<!-- Tier 2 of the portfolio (root workspace CLAUDE.md, "## Portfolio
     tiers") — Tier 1 is azure-cost-sentinel through entra-identity-monitor
     (projects 1-6), Tier 2 is this project + landing-zone-foundation +
     event-driven-alert-pipeline, Tier 3 is reserved/not yet scoped.
     TODO: exact footer cross-link format (shared list vs. per-tier lists)
     decided when Tier 2 ships. -->
