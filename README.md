<!--
SKELETON — filled progressively during the build.
Recruiter-facing. Structure matches the sibling portfolio projects.
Every claim must be literally true. Placeholders only — no real IDs / tenant domain.
-->

# Terraform Storage Baseline

> A reusable, versioned Terraform module for a secure-by-default Azure
> storage account, plus an example root module that consumes it — the
> portfolio's first non-Bicep IaC project.

<!-- badges: Azure, Terraform, cost -->

## The problem

<!-- TODO: a storage account created with defaults is not secure by default
     (TLS version, public blob access, HTTPS enforcement, versioning/
     lifecycle all need explicit configuration). A hand-run checklist doesn't
     scale past one project; a module does. -->

## What it does

<!-- TODO after build. Bullet list:
     - Terraform module: secure-by-default Azure storage account
       (HTTPS-only, TLS 1.2+, public blob access disabled, versioning +
       lifecycle policy)
     - example root module consuming the module with realistic variables
     - module published with semantic version tags -->

## Architecture

<!-- TODO: module input/output diagram or a short description of the module
     boundary (variables in, resource + outputs out). -->

**Services used:** Azure Storage · Terraform (azurerm provider).

**Auth:** <!-- TODO: how the example root module authenticates
     (az CLI auth vs service principal), least-privilege scope. -->

## Environment

<!-- TODO: runs against the live Azure subscription behind the portfolio for
     the apply/destroy validation cycle, not a disposable sandbox. -->

## What this doesn't do

<!-- TODO, expect at minimum:
     - not a general-purpose storage module — narrowly scoped to the
       secure-by-default baseline, not every possible storage account
       configuration
     - no standing resource — validated via apply/destroy, not left running
     - no remote state backend automation (documented, not built) -->

## Running it yourself

<!-- TODO: terraform init/plan/apply steps, prerequisites, module source
     reference syntax for consuming it from another root module. -->

## Sample output

<!-- TODO: terraform plan/apply output excerpt, with identifiers cropped. -->

## Cost

<!-- TODO with real measured numbers. Design estimate: near-zero — a storage
     account at rest with no data written is fractions of a cent; the
     validation cycle applies and destroys rather than leaving it running. -->

## Tests

<!-- TODO: what's validated and how — terraform validate, terraform plan,
     any policy/compliance checks (e.g. tflint, checkov). -->

## CI

<!-- TODO: validation-only CI (terraform fmt -check, terraform validate),
     no apply pipeline — consistent with the portfolio's no-standing-deploy-
     identity stance even though the tool differs. -->

## Built with

Designed and reviewed with Claude (architecture, spec-tightening, this
README), implemented with Claude Code and the Terraform CLI in VS Code.
[`REVIEW.md`](REVIEW.md) is the running build log.

---

## Portfolio series

<!-- Tier 2 of the portfolio (root workspace CLAUDE.md, "## Portfolio
     tiers") — Tier 1 is azure-cost-sentinel through entra-identity-monitor
     (projects 1-6), Tier 2 is this project + landing-zone-foundation +
     event-driven-alert-pipeline, Tier 3 is reserved/not yet scoped.
     TODO: exact footer cross-link format (shared list vs. per-tier lists)
     decided when Tier 2 ships. -->
