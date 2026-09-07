variable "subscription_id" {
  description = "Target Azure subscription ID. Prefer the ARM_SUBSCRIPTION_ID environment variable; never commit a real value."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "location" {
  description = "Azure region. Matches the rest of the portfolio."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Resource group to create."
  type        = string
  default     = "rg-storage-baseline-dev"
}

variable "name_prefix" {
  description = <<-EOT
    Storage account name prefix, before the uniqueness suffix.

    The portfolio convention is st-<slug>-<env>, but "storage-baseline" would
    give "ststoragebaselinedev" (20 chars) — leaving 4 characters of a 24-char
    ceiling for uniqueness, and stuttering st/storage. The `storage` token is
    dropped for storage accounts only. See azure-naming-conventions.md.
  EOT
  type        = string
  default     = "stbaselinedev"

  validation {
    condition     = can(regex("^[a-z0-9]{3,18}$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric and leave room for a 6-character suffix inside the 24-character limit."
  }
}

variable "allowed_ip_ranges" {
  description = <<-EOT
    Public IPv4 addresses permitted through the storage firewall.

    The module denies by default, so leaving this empty means no client can
    reach the blob data plane from the internet — including you. Set it to your
    own egress address to browse the account after apply. It is not
    auto-detected: an implicit outbound call to an IP-echo service at plan time
    would be a poor thing to hide inside infrastructure code.

    Azure rejects RFC1918 ranges and /31 and /32 prefixes here.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Portfolio-standard tags. See azure-naming-conventions.md."
  type        = map(string)
  default = {
    portfolio   = "azure-devops-portfolio"
    project     = "storage-baseline"
    environment = "dev"
  }
}

variable "assign_data_plane_role" {
  description = <<-EOT
    Whether to grant the caller Storage Blob Data Contributor on the account.

    Creating a role assignment requires Owner or User Access Administrator at
    the scope. Set false if the deploying identity only holds Contributor —
    the apply will otherwise fail on the assignment, not on the storage account.
  EOT
  type        = bool
  default     = true
}
