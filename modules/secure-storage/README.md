# `secure-storage`

A secure-by-default Azure storage account. Supply a name, a resource group and
a location; every security control is already set.

```hcl
module "storage" {
  source = "github.com/realitylvn/terraform-storage-baseline//modules/secure-storage?ref=v1.0.0"

  name                = "stbaselinedevab12cd"
  resource_group_name = azurerm_resource_group.this.name
  location            = "eastus2"

  tags = {
    portfolio   = "azure-devops-portfolio"
    project     = "storage-baseline"
    environment = "dev"
  }
}
```

That call alone produces an account with HTTPS-only transport, a TLS 1.2 floor,
anonymous blob access disabled, shared access keys disabled, double encryption
at rest, blob versioning with soft delete, a firewall that denies by default,
and a lifecycle policy that keeps versioning from growing without bound.

## Three tiers of control

Not every setting is a variable, and that is the design.

**Tier A — fixed. No variable exists.** Overriding these would mean you do not
want this module:

| Setting | Value |
|---|---|
| `https_traffic_only_enabled` | `true` |
| `allow_nested_items_to_be_public` | `false` |
| container `container_access_type` | `private` |

**Tier B — variable, validated to refuse an insecure value.** `min_tls_version`
rejects `TLS1_0` and `TLS1_1`: the variable exists so the floor can be raised,
not lowered. It currently also rejects `TLS1_3`, for an unrelated reason —
azurerm 4.81 accepts only `TLS1_0`, `TLS1_1` and `TLS1_2` for this field, so
validating it here turns an opaque provider error into a clear one. When the
provider adds `TLS1_3`, add it to the allowed set and nothing else changes.
`account_kind`, `account_tier`, `access_tier`, `account_replication_type` and
both soft-delete retention windows are range- or set-checked.

**Tier C — free variables.** Name, resource group, location, tags, containers,
lifecycle rules, network allowlists, replication choice.

## Two things that will surprise you

**Shared access keys are disabled by default.** `shared_access_key_enabled`
defaults to `false`, so connection strings do not work and the Portal will not
list blobs until the caller holds a data-plane role.

This is worth stating precisely, because it is the most commonly confused
distinction in Azure storage: a **control-plane** role — `Owner`,
`Contributor`, `Storage Account Contributor` — lets a principal manage the
account *resource* and grants nothing at all on the *data* inside it. Reading a
blob requires a **data-plane** role such as `Storage Blob Data Reader` or
`Storage Blob Data Contributor`. Holding one implies nothing about the other,
and conflating them produces a 403 against a token that looks perfectly valid.

```hcl
resource "azurerm_role_assignment" "reader" {
  scope                = module.storage.id   # the account, not the resource group
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "User"
}
```

Set `shared_access_key_enabled = true` if a consumer genuinely needs a
connection string. Doing so relaxes that control and nothing else.

**The firewall denies by default.** `network_default_action` is `Deny`, so an
account created with no `allowed_ip_ranges` is unreachable from the internet —
including by you. Add your own public egress address to browse it:

```hcl
allowed_ip_ranges = ["203.0.113.10"]
```

Azure rejects RFC1918 private ranges here, and rejects `/31` and `/32` prefixes
— pass a bare address rather than `x.x.x.x/32`.

This is a *firewall-restricted* public endpoint, not a private one. Genuine
network isolation needs Private Link, which is out of scope for this module —
see the repository README.

## Versioning and the cost it hides

`blob_versioning_enabled` defaults to `true`, which is a data-protection win and
an unbounded cost-growth bug in equal measure: every overwrite retains a
billable previous version indefinitely, and nothing in Azure cleans them up.

So the default `lifecycle_rules` value ships a policy that makes versioning
safe rather than expensive:

- base blobs move to cool at 30 days and archive at 90 days, and are **never
  deleted**
- previous versions are deleted at 90 days
- snapshots are deleted at 90 days

Live data is only ever tiered down, never removed. Pass `lifecycle_rules = []`
to create no policy at all — but if you do that while versioning is on, you own
the growth.

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | `string` | — | Required. 3-24 lowercase alphanumerics, globally unique. |
| `resource_group_name` | `string` | — | Required. Must already exist. |
| `location` | `string` | — | Required. |
| `tags` | `map(string)` | `{}` | |
| `min_tls_version` | `string` | `"TLS1_2"` | Only `TLS1_2` is currently accepted. |
| `account_kind` | `string` | `"StorageV2"` | `StorageV2` or `BlockBlobStorage`. |
| `account_tier` | `string` | `"Standard"` | |
| `account_replication_type` | `string` | `"LRS"` | |
| `access_tier` | `string` | `"Hot"` | |
| `shared_access_key_enabled` | `bool` | `false` | See above. |
| `infrastructure_encryption_enabled` | `bool` | `true` | Immutable after creation. |
| `identity_type` | `string` | `"SystemAssigned"` | `SystemAssigned` or `None`. |
| `public_network_access_enabled` | `bool` | `true` | |
| `network_default_action` | `string` | `"Deny"` | |
| `network_bypass` | `set(string)` | `["AzureServices"]` | |
| `allowed_ip_ranges` | `list(string)` | `[]` | Public addresses only. |
| `allowed_subnet_ids` | `list(string)` | `[]` | Requires a service endpoint. |
| `blob_versioning_enabled` | `bool` | `true` | |
| `blob_change_feed_enabled` | `bool` | `false` | Has its own storage cost. |
| `blob_last_access_time_enabled` | `bool` | `false` | Needed for last-access lifecycle rules. |
| `blob_soft_delete_retention_days` | `number` | `7` | 1-365. |
| `container_soft_delete_retention_days` | `number` | `7` | 1-365. |
| `containers` | `map(object)` | `{}` | Keys are container names. |
| `lifecycle_rules` | `list(object)` | see above | `[]` creates no policy. |

## Outputs

`id`, `name`, `primary_blob_endpoint`, `primary_blob_host`,
`identity_principal_id`, `container_names`, and `security_posture` — a map of
the controls actually applied, read back from the provider so a consumer or a
test can assert on the baseline rather than trust this document.

## Requirements

Terraform `>= 1.9.0`, `hashicorp/azurerm >= 4.0.0, < 5.0.0`. The module
declares no provider block; configure `azurerm` in your root module.

## Tests

```
cd modules/secure-storage
terraform test
```

`tests/defaults.tftest.hcl` asserts the secure defaults hold with minimal
input, `tests/validation.tftest.hcl` asserts insecure input is refused, and
`tests/overrides.tftest.hcl` asserts the documented opt-outs work and stay
scoped. All run at `command = plan` — no resource is created.
