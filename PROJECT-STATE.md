# Project State — terraform-storage-baseline

**Current objective:** A reusable, versioned Terraform module for a
secure-by-default Azure storage account, plus an example root module that
consumes it. Portfolio Tier 2, first non-Bicep IaC project. Design per
`docs/internal/specs/2026-09-07-terraform-storage-baseline-design.md`.

**Completed milestone:** Checkpoints 1-4 (2026-09-07) — scaffold, module, and
the test/CI layer, plus a live-subscription plan. **Nothing deployed; no Azure
resource created or changed.** Validated against the provider schema, a mocked
provider, and a real `terraform plan`.

1. Pre-flight (`cloud-preflight-review`) done. `azure-naming-conventions.md`
   written (was missing), including a Terraform-specific identifier-hazard
   section that has no Bicep equivalent.
2. Terraform 1.16.1 installed — it was not present on this machine, and no
   package manager was either. Downloaded direct from HashiCorp,
   checksum-verified against the published `SHA256SUMS`, extracted to
   `C:\Users\LVN\bin`, added to the persistent user PATH.
3. `git init` done. `.gitignore` covers `*.tfstate`, `*.tfvars`, `*.tfplan`,
   `.terraform/`, `docs/internal/`, `prompt.md`, `.azure/`; every rule verified
   with `git check-ignore`. `.terraform.lock.hcl` deliberately committed.
4. `modules/secure-storage` authored — storage account, containers, lifecycle
   policy. `terraform fmt` and `validate` clean against azurerm 4.81.0.
5. 22 `terraform test` assertions across three files, all passing, exit code 0.
6. `examples/complete` root module authored and validated.
7. `.github/workflows/validate.yml` (fmt, validate, test, tflint, Checkov) and
   `.tflint.hcl`. No apply job, no deploy credential.
8. `docs/architecture.md` written and verified in both GitHub themes with
   `verifying-mermaid-diagrams`; a label collision was found and fixed.
9. REVIEW.md Checkpoints 1-4 written with the command log; README and
   docs/architecture.md filled.
10. Checkpoint 4 — `terraform plan` against the live subscription: 7 to add,
    0 to change, 0 to destroy, exit 0. Read-only; created nothing.

**Settled design decisions** (confirmed by Jonathan 2026-09-07, full reasoning
in the spec and REVIEW.md):

- **D1** — `shared_access_key_enabled = false` by default. Entra ID data-plane
  auth only; consumers opt in to keys.
- **D2** — Public endpoint with `network_default_action = "Deny"` and an IP
  allowlist. Private Link is out of scope on cost and standalone-scope grounds.
  The README must say *firewall-restricted*, never *private*.
- **D3** — Three validation layers: `terraform test`, `tflint`, Checkov.

**Naming — settled.** Slug is `storage-baseline`. Storage *account* names drop
the `storage` token (`stbaselinedev<suffix>`) to avoid `st`/`storage` stutter
inside the 24-character ceiling; the resource group keeps the full slug
(`rg-storage-baseline-dev`).

**Two findings worth carrying forward:**

- The azurerm provider acquires a token when it is **configured**, not when a
  resource is planned, so even `command = plan` tests need a live credential
  with a real provider block. Verified against a bogus tenant. The tests use
  `mock_provider` so CI needs no Azure credential, which keeps the standing
  no-federated-deploy-identity decision intact. The trade — mocks cannot catch
  a value the provider would reject — is covered by a real `terraform plan` at
  Checkpoint 4.
- Piping `terraform test` to another command masks its exit code. The first run
  reported exit 0 with three failures. CI does not pipe.

**Next action:** Checkpoint 5 — the hard gate. `terraform apply` on
`examples/complete` creates 7 real resources and does NOT run without
Jonathan's explicit go-ahead.

**Blockers:** none. Checkpoint 5 is a **hard gate**: `terraform apply` does not
run without Jonathan's explicit go-ahead.

**Manual prerequisite for apply (Checkpoint 6):** creating the role assignment
needs `Owner` or `User Access Administrator` at the scope. If the account only
holds `Contributor`, set `assign_data_plane_role = false` — otherwise the apply
fails on the assignment rather than on the storage account.

**Cost position:** design estimate $0.00/month. An empty StorageV2 LRS account
has no hourly meter; billing is per-GB-stored and per-transaction. Validated by
an apply/destroy cycle, not left standing. No new Budget —
`azure-cost-sentinel` owns the one subscription-wide Budget. Real number
recorded in REVIEW.md after Checkpoint 6.

**Verification state:** `fmt`, `validate`, and 22 mocked `terraform test`
assertions pass locally, exit code 0 confirmed without a pipe. `terraform plan`
against the live subscription succeeds: 7 to add, 0 to change, 0 to destroy,
exit 0, every security control resolving as intended. `tflint` and Checkov are
configured but have NOT been run — neither is installed locally, so their first
real run is in GitHub Actions. No apply.

**Canonical checkout:**
`c:\Users\LVN\Documents\Coding Workspace\Azure\terraform-storage-baseline`,
branch `master` (no remote, not published).

**Relationship to the paused projects:** this project was picked precisely
because `landing-zone-foundation`'s PROJECT-STATE parked its own resumption on
finding work that could proceed without touching the shared tenant. Starting it
is a continuation of that decision, not a departure from strict build order.
Neither paused project is affected by anything here.
