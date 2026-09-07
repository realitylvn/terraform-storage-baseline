# Terraform Storage Baseline — build review & learning log

Personal study companion to this project. Unlike `README.md` (public /
recruiter-facing), this file tracks *why* each decision was made and logs
every `terraform` / `az` command as it runs, so the reasoning isn't
reconstructed from memory afterwards. Written progressively at each build
checkpoint, same as the rest of the portfolio.

IDs in commands and pasted output are redacted to placeholders
(`<SUBSCRIPTION_ID>`, `<TENANT_ID>`, `<PRINCIPAL_ID>`) **at the moment of
capture**, not in a later pass.

---

## What this is

Standalone intermediate-tier portfolio project. A reusable, versioned
Terraform module for a secure-by-default Azure storage account, plus an
example root module that consumes it. The portfolio's first Terraform
project — everything prior is Bicep — so the point is demonstrating module
design and reusability, not rebuilding an existing tool.

Does not fork or extend any prior project's scaffold.

---

## Checkpoint 1 — scaffold, pre-flight, and design

### Why this project was started now

Two projects were already in flight and both are paused on the same problem:
tenant-wide changes reaching accounts and people outside the portfolio.
`entra-identity-monitor` is paused before Task 14 because disabling security
defaults would remove MFA enforcement from five accounts belonging to other
people. `landing-zone-foundation` is paused before its subscription move, and
its `PROJECT-STATE.md` records the reason as wanting to "pick one [project]
that can kick off with minimal impact *before* a security baseline is
introduced to the tenant."

This project is the answer to that recorded question, not a departure from the
portfolio's strict build order. It is resource-group scoped, creates no Entra
object, changes no tenant setting, and makes exactly one role assignment scoped
to a single resource it creates itself.

### Pre-flight (cloud-preflight-review)

| Check | Result |
|---|---|
| Subscription | `LVN Subscription`, Enabled — same subscription as every sibling. Region `eastus2` to match. |
| Quota | Not applicable. No compute SKU. Storage accounts cap at 250/region; 4 existed. |
| Naming convention | `azure-naming-conventions.md` did not exist. Written before any resource was named. |
| Architecture doc | Written, house Mermaid style, verified in both GitHub themes. |
| Identifier scan | Run before the first commit. |
| Repo scope | `docs/internal/` and `prompt.md` gitignored, verified with `git check-ignore`. |

### Terraform is not installed anywhere in this workspace

The first genuine finding, and it says something about the project: every prior
portfolio project used Bicep, which ships inside the Azure CLI. Terraform is a
separate toolchain with its own installation, its own version pinning and its
own state model, and none of that existed on this machine.

No package manager was available either (`winget` and `choco` both absent from
PATH), so the install was a direct download from HashiCorp, **checksum-verified
against the published `SHA256SUMS`** before extraction. Verifying the checksum
of a binary downloaded over the internet is the whole point of HashiCorp
publishing it; skipping that step because the download "looked fine" is how
supply-chain compromise works.

### The naming problem this project has and its siblings did not

The portfolio pattern is `<abbreviation>-<slug>-<env>`. Applied naively here it
produces `st` + `storagebaseline` + `dev` = `ststoragebaselinedev` — 20
characters against a hard 24-character ceiling for storage account names,
leaving 4 characters for a global-uniqueness suffix, and stuttering `st`
against `storage`.

The convention already anticipates this: it says not to repeat a token the slug
already carries (`nsg-scanner`, not `nsg-nsg-scanner`). So the `storage` token
is dropped from storage *account* names only, giving `stbaselinedev<suffix>` at
19 characters. The resource group keeps the full slug — `rg-storage-baseline-dev`
has no length ceiling and no stutter, because `rg` is not a prefix of `storage`.

### Terraform leaks identifiers in a way Bicep never did

This deserved its own section in `azure-naming-conventions.md`. `terraform.tfstate`
is plaintext JSON containing the subscription ID, every resource ID, and — for a
storage account specifically — **the primary and secondary access keys**. Bicep
produces no comparable artifact; there is nothing in the Bicep workflow that
writes credentials to a file in the working directory as a matter of course.

`.gitignore` therefore covers `*.tfstate`, `*.tfstate.*`, `*.tfvars`, `*.tfplan`
and `.terraform/`, and each rule was verified rather than assumed:

```
$ for f in terraform.tfvars terraform.tfvars.example terraform.tfstate \
           .terraform.lock.hcl prompt.md docs/internal/specs/x.md; do
    printf "%-34s " "$f"; git check-ignore -q "$f" && echo "IGNORED" || echo "committed"
  done
terraform.tfvars                   IGNORED
terraform.tfvars.example           committed
terraform.tfstate                  IGNORED
.terraform.lock.hcl                committed
prompt.md                          IGNORED
docs/internal/specs/x.md           IGNORED
```

`.terraform.lock.hcl` is deliberately **not** ignored. It pins provider version
hashes, contains no identifiers, and is exactly the kind of file that should be
committed so a build is reproducible.

### AZ-900 / AZ-104 domains touched at this checkpoint

- **Manage Azure identities and governance** — resource naming and tagging
  standards, subscription confirmation before any change.
- **Describe Azure architecture and services** — resource group as a scope
  boundary; storage account naming as a global namespace.
- **General security practice** — supply-chain verification of a downloaded
  binary; secret hygiene in version control.

---

## Checkpoint 2 — the module

### The design argument: not everything should be a variable

A Terraform module that exposes every provider setting as an input is a thin
wrapper around the provider that guarantees nothing. A module that exposes
nothing cannot be reused. The opinion lives in the tiering, so the module sorts
its surface into three tiers deliberately:

**Tier A — fixed, no variable exists.** `https_traffic_only_enabled = true`,
`allow_nested_items_to_be_public = false`, and container `container_access_type
= "private"`. There is no legitimate reason to want a "secure-by-default
storage baseline" that serves plaintext HTTP or anonymous blobs. Overriding
these would mean you want a different module.

**Tier B — a variable whose validation refuses an insecure value.**
`min_tls_version` exists so the floor can be raised, never lowered.
`account_kind` refuses legacy kinds that cannot support versioning or soft
delete. Retention windows are range-checked. Container names are regex-checked
against Azure's actual rules rather than failing at apply time.

**Tier C — genuinely free.** Name, resource group, location, tags, containers,
lifecycle rules, network allowlists, replication choice.

### Disabling account keys forces the interesting problem

`shared_access_key_enabled` defaults to `false`. That single default is what
makes this a security baseline rather than a naming convention, and it has a
consequence the example root module cannot dodge: the account is *unusable* on
creation until a principal is granted a data-plane role.

That is the correct failure mode. Access is granted deliberately rather than
inherited by whoever happens to be able to manage the resource.

It also puts the portfolio's most expensive past bug directly in the example.
`azure-drift-detector` held `Cost Management Reader` — a **control-plane** role
— and authenticated to a blob with the same managed identity, getting a silent
403. `azure-cost-sentinel` had the same bug, forked. A control-plane role
(`Owner`, `Contributor`, `Storage Account Contributor`) authorises management of
the account *resource* through ARM and grants nothing whatsoever on the *blobs
inside it*. Reading a blob needs a **data-plane** role. Here the example assigns
`Storage Blob Data Contributor`, scoped to the storage account rather than the
resource group, with `principal_type` set explicitly so the assignment does not
fail on Entra replication lag.

A second-order effect worth recording: with keys disabled, `azurerm_storage_container`
must be given `storage_account_id` rather than `storage_account_name`. The two
arguments select different code paths in the provider — the name form talks to
the blob data plane and needs a key or a data role that does not exist yet
during the same apply, while the ID form provisions through Resource Manager.

### Versioning on by default is a cost bug unless a policy ships with it

Blob versioning is a data-protection win and an unbounded cost-growth bug in
equal measure: every overwrite retains a billable previous version indefinitely
and nothing in Azure cleans them up. Turning it on by default and stopping there
would hand every consumer a bill that grows forever.

So the default lifecycle policy is deliberately safe rather than aggressive.
Base blobs are tiered to cool at 30 days and archive at 90 days and are **never
deleted**; previous versions and snapshots are pruned at 90 days. Live data is
only ever moved to cheaper storage, never removed. A test asserts this
specifically, because a well-meaning edit that added a base-blob delete rule
would look like tidy housekeeping and would silently start destroying consumer
data.

### Verified

```
$ terraform init      # provider resolved to hashicorp/azurerm v4.81.0
$ terraform fmt -check -recursive
$ terraform validate
Success! The configuration is valid.
```

`terraform validate` failed first on `delete_after_days_since_creation` in the
`snapshot` block. The provider schema was the authority, not memory or
documentation:

```
$ terraform providers schema -json > schema.json
$ grep -o '"[a-z_]*days_since_creation[a-z_]*"' schema.json | sort -u
"delete_after_days_since_creation"
"delete_after_days_since_creation_greater_than"
```

azurerm names this attribute `delete_after_days_since_creation` on `version` but
`delete_after_days_since_creation_greater_than` on `snapshot`. That asymmetry is
in the provider, not in this code; the module absorbs it so consumers pass one
consistent pair of variables. The reason is written as a comment at the call
site, because it reads exactly like copy-paste drift and would otherwise get
"fixed" by a future edit.

### AZ-900 / AZ-104 domains touched at this checkpoint

- **Configure and manage storage** — account kinds and tiers, replication
  options, blob versioning, soft delete, lifecycle management, storage
  firewall.
- **Manage Azure identities and governance** — RBAC role assignment, scope
  selection, and the control-plane / data-plane distinction.
- **Implement and manage infrastructure as code** — module composition, input
  validation, resource preconditions, provider version constraints.

---

## Checkpoint 3 — tests, and a CI assumption that turned out to be wrong

### What the tests are for

`terraform validate` checks syntax and types. It would not notice
`min_tls_version` being flipped to `TLS1_0`, which is the exact regression this
project exists to prevent. So the module carries 22 `terraform test` assertions
across three files: the secure defaults hold with minimal input, insecure input
is refused, and the documented opt-outs work without silently relaxing anything
else.

The first run failed three of them, and all three were worth having:

1. **`TLS1_3` is not accepted by azurerm 4.81.** The variable validation had
   been written to allow `TLS1_2` and `TLS1_3` on the reasoning that raising the
   floor should always be permitted. The provider accepts only `TLS1_0`,
   `TLS1_1` and `TLS1_2` for this field, so `TLS1_3` failed *inside* the
   provider with a much less obvious error. The validation now refuses it at the
   variable, with an error message that distinguishes the two reasons —
   `TLS1_0`/`TLS1_1` are refused on security grounds, `TLS1_3` because the
   provider does not yet support it. Documentation that claimed otherwise was
   corrected in the same pass.

2. **An unset day-count is `-1`, not `null`.** The assertion that the default
   policy never deletes live base blobs compared against `null` and got `-1` —
   azurerm normalises "unset" to a sentinel. Comparing `null` with `<=` is an
   error in Terraform, so the fix is `coalesce(x, -1) <= 0`, which also handles
   the mocked case discussed below.

3. **An unconfigured attribute is unknown at plan time.** Asserting that no
   `network_rules` block is emitted could not be done against
   `azurerm_storage_account.this.network_rules`: with no block in the config,
   the provider marks the whole attribute computed, so its value is genuinely
   unknown until apply. The assertion moved to the module's `security_posture`
   output, which is derived from the same local that decides whether to emit the
   block and is therefore known at plan.

The `security_posture` output exists partly for this reason. It reports the
controls actually applied so a consumer, a test or a reviewer can assert on the
baseline rather than trust the README.

### The CI assumption that was wrong

The CI workflow was first written asserting that `terraform test` needs no Azure
credential, on the reasoning that `command = plan` creates nothing and therefore
calls nothing. That claim was checked rather than shipped, by running the suite
against a bogus tenant with an empty CLI config directory:

```
$ ARM_TENANT_ID=<BOGUS> ARM_CLIENT_ID=<BOGUS> ARM_CLIENT_SECRET=<BOGUS> \
  AZURE_CONFIG_DIR=<EMPTY_DIR> terraform test
Error: building account: could not acquire access token to parse claims:
  ... AADSTS90002: Tenant '<BOGUS>' not found ...
Failure! 0 passed, 0 failed, 22 skipped.
```

The assumption was false. The azurerm provider acquires an access token when it
is **configured**, before any resource is planned — so a real `provider` block
makes even a plan-only test require a live credential.

That mattered, because it collided head-on with the portfolio's standing
decision that this repository has no federated deploy identity. The options were
to give CI an Azure credential (breaking that decision), to drop the tests from
CI (losing the only check that would catch the regression the project is about),
or to remove the provider from the tests entirely.

The third is what `mock_provider` is for. The test files now declare
`mock_provider "azurerm" {}`, and the same bogus-credential run passes:

```
$ ARM_TENANT_ID=<BOGUS> ... terraform test
Success! 22 passed, 0 failed.
exit code 0
```

**The trade is real and is written into the test file rather than glossed.**
Mocked tests assert this module's own configuration logic, not the provider's
behaviour, so they structurally cannot catch a value the provider would reject —
which is to say they would not have caught the `TLS1_3` bug above. Provider
acceptance is therefore proved separately by `terraform plan` against the live
subscription, a workstation step rather than a CI one. Layered that way, each
check covers the other's blind spot.

A smaller but sharp lesson from the same episode: the very first test run
reported `exit code 0` while three tests were failing, because the command was
piped to `tail` and the pipeline returned `tail`'s status. A CI job written that
way would have been permanently, invisibly green.

### Third-party confirmation

`tflint` (with the azurerm ruleset) and `Checkov` run in CI alongside the
native tests. The reasoning is that a module should not be the only thing
asserting that the module is secure — Checkov checks against recognised CIS
storage benchmarks maintained by people with no stake in this repository.

### AZ-900 / AZ-104 domains touched at this checkpoint

- **Implement and manage infrastructure as code** — automated testing of
  infrastructure definitions, provider mocking, CI validation gates.
- **General security practice** — verifying a security claim instead of
  asserting it; layering an independent benchmark over self-authored checks.

---

## Checkpoint 4 — plan against the live subscription

This is the layer the mocked tests structurally cannot cover: whether the real
azurerm provider and the real Azure API accept what the module produces.
`terraform plan` reads and creates nothing.

```
$ export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
$ terraform plan -var="subscription_id=<SUBSCRIPTION_ID>" \
                 -var='allowed_ip_ranges=["203.0.113.10"]'

  # azurerm_resource_group.this will be created
  # azurerm_role_assignment.caller_blob_data[0] will be created
  # random_string.suffix will be created
  # module.storage.azurerm_storage_account.this will be created
  # module.storage.azurerm_storage_container.this["artifacts"] will be created
  # module.storage.azurerm_storage_container.this["logs"] will be created
  # module.storage.azurerm_storage_management_policy.this[0] will be created

Plan: 7 to add, 0 to change, 0 to destroy.
```

Exit code 0. Every control resolved as intended:

```
+ account_kind                      = "StorageV2"
+ account_replication_type          = "LRS"
+ allow_nested_items_to_be_public   = false
+ https_traffic_only_enabled        = true
+ infrastructure_encryption_enabled = true
+ min_tls_version                   = "TLS1_2"
+ public_network_access_enabled     = true
+ shared_access_key_enabled         = false
+ default_action                    = "Deny"     # network_rules
```

and the role assignment is scoped and typed as designed:

```
+ role_definition_name = "Storage Blob Data Contributor"
+ principal_type       = "User"
+ scope                = (known after apply)     # the storage account
```

The plan also confirms the `-1` sentinel behaviour that a test assertion had to
be rewritten for: every unset day-count in the lifecycle policy resolves to
`-1`, while the three configured values come through as `30`, `90` and `90`.
Base-blob deletion is `-1` — the default rule does not delete live data, as
intended.

### A leak `terraform plan` introduces that Bicep did not

The plan output contained a bare GUID. It was not the subscription or tenant
ID, both of which were already being redacted at capture:

```
+ principal_id = "<PRINCIPAL_ID>"
```

It is the signed-in user's own **object ID**, pulled in by
`data.azurerm_client_config.current` and printed in full because the role
assignment consumes it. This is exactly the identifier class the portfolio
convention names, and it appears in ordinary plan output without any command
that obviously asks for it. `az deployment what-if` on the equivalent Bicep
would not surface it, because the Bicep projects pass a principal ID in rather
than reading the caller's.

Redacted at capture. The practical rule this adds: **any Terraform plan output
pasted into a document, a PR or a screenshot needs a principal-ID pass, not
just a subscription-ID pass** — and a plan file saved with `-out` embeds the
same value in binary form, which is a further reason `*.tfplan` is gitignored.

### AZ-900 / AZ-104 domains touched at this checkpoint

- **Implement and manage infrastructure as code** — plan/apply lifecycle,
  reading a plan as a review artifact rather than a formality.
- **Manage Azure identities and governance** — RBAC scope resolution;
  identifier hygiene in tooling output.

**Next: Checkpoint 5 is a hard gate.** `terraform apply` creates real resources
and does not run without explicit go-ahead.

---

<!-- Further checkpoints appended here as the build proceeds. -->

---

## Command log

| Command | What it did / why |
|---|---|
| `az account show` | Confirmed the target subscription before anything else. `LVN Subscription`, Enabled, `<SUBSCRIPTION_ID>`. |
| `az storage account list -o table` | Surveyed existing storage accounts; confirmed the naming pattern in use and that nothing collided. |
| `az group list -o table` | Confirmed `rg-storage-baseline-dev` did not already exist. |
| `curl .../terraform/1.16.1/..._SHA256SUMS` + `sha256sum` | Checksum-verified the Terraform download before extracting. Matched. |
| `git init` / `git check-ignore -v` | Initialised the repo and **verified** each ignore rule rather than trusting the file. |
| `terraform init` | Resolved `hashicorp/azurerm` to v4.81.0 and wrote `.terraform.lock.hcl`. |
| `terraform providers schema -json` | Read the provider's real schema to settle the `snapshot` vs `version` attribute-name asymmetry. Documentation and memory were not treated as authoritative. |
| `terraform fmt -check -recursive -diff` | Formatting gate; clean repo-wide. |
| `terraform validate` | Module and example both valid. |
| `terraform test` (real provider) | 22 assertions. Caught the `TLS1_3`, `-1` sentinel and unknown-at-plan issues. |
| `terraform test` (bogus tenant, empty `AZURE_CONFIG_DIR`) | Disproved the assumption that plan-only tests need no credential. 22 skipped, provider failed at configure. |
| `terraform test` (with `mock_provider`) | Same bogus credentials: 22 passed, exit 0. Proved CI needs no Azure credential. |
| `npx @mermaid-js/mermaid-cli` | Parse-checked the architecture diagram and rendered both GitHub themes; fixed a label collision found by actually looking at the output. |
| `terraform plan` (examples/complete, live subscription) | Checkpoint 4. 7 to add, 0 to change, 0 to destroy; every security control resolved as intended. Created nothing. |
| `az ad signed-in-user show --query id` | Identified the bare GUID left in plan output as the caller object ID, then redacted it at capture. |

---

## Measured cost

<!-- TODO after the real apply/destroy cycle (Checkpoint 6). Design estimate:
     $0.00/month — an empty StorageV2 LRS account has no hourly meter, and
     billing is per-GB-stored and per-transaction. Validated by apply/destroy,
     not left standing. No new Budget: azure-cost-sentinel owns the one
     subscription-wide Budget by standing portfolio decision. -->

---

## AZ-900 / AZ-104 domain mapping

<!-- TODO: consolidated at the end, scored against what the build actually
     exercised. Per-checkpoint mappings are recorded above as they happen. -->
