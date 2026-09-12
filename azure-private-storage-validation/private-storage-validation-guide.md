# Part 2: Private Storage with Private Endpoint — Build Guide

Region: your choice (default `<your-region>` in `variables.tf`) · Terraform 1.15.8 · azurerm ~>5.1

Work through this top to bottom. Each step has: **what it is**, **why it exists**, then the exact code/commands. Don't skip the "why" — it's the part worth understanding, not just copying.

This build deploys a Storage Account with **no public network access**, reachable only through a **Private Endpoint** inside the spoke VNet, with **Private DNS** wiring so the storage name resolves to a private IP. To keep cost near zero it deliberately skips the VM and Bastion — you can prove the private-storage pattern without either.

**Every code block can be copied exactly as written, except these 2 spots** — marked again inline where they occur:

| # | Where | What to enter | When you'll have it |
|---|---|---|---|
| 1 | `variables.tf` and each module's `variables.tf` → `location` default | Your chosen Azure region (e.g. `eastus`, `uksouth`, `centralindia`) | Anytime — pick one before Step 5 |
| 2 | `backend.tf` → `resource_group_name`, `storage_account_name`, `container_name` | Your state backend's real names | From Step 1 — reuse an existing backend, or read the fresh bootstrap output |

Everything else — resource names, address spaces, the storage account name (random-suffixed) — is a fixed default.

---

## Step 0 — Prerequisites

**What:** Confirm your tools and identity are ready before writing any Terraform.

**Why:** Terraform needs to know *which* Azure subscription to act on, and it authenticates through your Azure CLI session — so a stale or wrong subscription context is the most common reason a first `apply` lands resources in the wrong place. There's no SSH key step here (unlike the landing-zone build) because this run has no VM.

```
az login
az account list --output table
az account set --subscription "<your-subscription-id>"
az account show --output table   # confirm the right subscription is active

terraform version                # confirm 1.15.8
```

> **Gotcha hit while building this:**
>
> If `az` commands start failing with `ResourceGroupNotFound` for a resource group you never created (something like `learn-c87f9371-...`), you've got a stale **default resource group** saved in your CLI config — usually left behind by an expired Microsoft Learn sandbox. It scopes every command to a group that no longer exists. Clear it once:
>
> ```
> az configure --list-defaults     # shows the stale group=... default
> az configure --defaults group="" # clears it
> ```

---

## Step 1 — Set up the remote state backend

**What:** Decide where Terraform stores its *state file* (its record of what infrastructure already exists) — either reuse a backend you already built, or create a fresh one.

**Why:** Terraform state can't live on your laptop long-term — it can't be shared, gets lost, and doesn't support locking (which stops two runs colliding). It belongs in a Storage Account. But that account is itself infrastructure, and Terraform can't store state in an account that doesn't exist yet — so it's always a one-time setup, done before everything else.

**First, check whether you already have a state backend:**

```
az storage account list \
  --query "[?starts_with(name, 'sttf')].{name:name, rg:resourceGroup}" -o table
```

- **If a state storage account is listed → Step 1A (reuse it).** This is the normal case if you've already built a landing zone.
- **If nothing is listed → Step 1B (bootstrap a fresh one).**

> **Gotcha:** search on a short prefix like `sttf`, not the full `sttfstate` — a naming convention like `sttflzstate…` (`lz` for "landing zone") won't match a `sttfstate` search, which can make it look like there's no backend when there actually is one.

---

### Step 1A — Reuse an existing backend (recommended if it exists)

**Why reuse:** a state backend is meant to be long-lived and shared across projects. One account holds many state files, kept apart by a unique `key` (the state file name). There's no benefit to a second account, and reusing keeps everything in one place.

Note the three values from the check above — resource group, storage account, container (usually `tfstate`). You'll paste them into `backend.tf` in Step 4. Nothing to create here.

If the account exists but has no `tfstate` container yet, create it once:

```
az storage container create \
  --name tfstate \
  --account-name <your-existing-tfstate-sa> \
  --auth-mode login
```

**Then skip Step 1B and go to Step 2.**

---

### Step 1B — Bootstrap a fresh backend

Use this only if the check found nothing. It's a small, separate config that runs with **local** state (because it's the thing creating the remote backend).

**Folder:** `bootstrap/`

`bootstrap/versions.tf`

```
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}
```

`bootstrap/main.tf` — creates the resource group, a random-suffixed storage account (the name has to be globally unique), and the `tfstate` container. Blob versioning is on so a corrupted state can be rolled back.

```
resource "azurerm_resource_group" "state" {
  name     = "rg-tfstate-validation"
  location = "<your-region>"   # e.g. eastus, uksouth, centralindia — pick whichever fits your account/latency needs
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "state" {
  name                     = "sttfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
```

`bootstrap/outputs.tf` — prints the generated name so you can paste it into `backend.tf`, instead of hunting for it in the portal.

```
output "resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "container_name" {
  value = azurerm_storage_container.state.name
}
```

**Run it:**

```
cd bootstrap
terraform init
terraform validate
terraform apply
terraform output          # note storage_account_name for Step 4
cd ..
```

> **Gotcha:** `azurerm_storage_container` on the v5 provider takes `storage_account_id`, **not** the older `storage_account_name`. This is a real v4→v5 breaking change — several storage sub-resources switched the same way, so use `storage_account_id` everywhere.

---

## Step 2 — Scaffold the repo

**What:** The folder layout everything else lives in.

**Why the split:** modules (reusable network/storage building blocks) are kept separate from the root config that *calls* them with real values. Terraform merges every `.tf` in a folder into one config regardless of filename, so the file split below is purely for human readability — each file has one job.

```
azure-private-storage-validation/
├── bootstrap/                       ← only if you did Step 1B
│   ├── versions.tf
│   ├── main.tf
│   └── outputs.tf
├── modules/
│   ├── networking/
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   └── outputs.tf
│   └── private-storage/
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
├── versions.tf
├── providers.tf
├── backend.tf
├── variables.tf
├── locals.tf
├── main.tf
└── outputs.tf
```

| File | What it holds |
|---|---|
| `versions.tf` | Which Terraform + provider versions this code is built for (the pin). |
| `providers.tf` | How to talk to Azure — the `azurerm` provider config. |
| `backend.tf` | *Where* state is stored. Alone on purpose — it can't use variables and is hand-edited. |
| `variables.tf` | The inputs (region, RG name). Declaring a variable defines what can be passed in, not its value. |
| `locals.tf` | Computed/shared values like the common tag set. |
| `main.tf` | The actual resources and module calls — what gets built. |
| `outputs.tf` | Values printed after apply and read by the validation commands. |

Each folder under `modules/` repeats the same three-file shape: its own `variables.tf` (inputs), `main.tf` (resources), `outputs.tf` (return values). A module is an isolated scope — it never inherits the root's variables, so whatever `var.xxx` a module references, that module's own `variables.tf` must declare.

Create the empty folders now; the next steps fill them in.

---

## Step 3 — Pin Terraform and the provider

**What:** Declare which Terraform version and which `azurerm` plugin version this code is built for.

**Why:** Terraform itself knows nothing about Azure — the `azurerm` provider is a plugin that turns your `.tf` into real Azure API calls. Pinning its version is like pinning `requirements.txt`: it stops a future provider release from silently changing how your code behaves. `random` is pinned too, since the storage account name depends on it.

`versions.tf`

```
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```

---

## Step 4 — Configure the provider and point at remote state

**What:** Two small files — one telling Terraform *how* to authenticate to Azure, one telling it *where* to keep this project's state.

**Why they're separate:** provider config and backend config change for different reasons. The backend is the one file you hand-edit per account/environment, and it has a hard rule the provider block doesn't — so keeping it alone makes it easy to find and swap.

`providers.tf` — `features {}` is mandatory even when empty; the provider won't initialize without it. Auth comes from your Step 0 CLI session, so there's nothing else to set here for a single-user run.

```
provider "azurerm" {
  features {}
}
```

`backend.tf` — this is the **one place you substitute your own values** (the account from Step 1). The `key` is a filename; keeping it unique is what lets this project's state sit in the same account as any other without colliding.

```
terraform {
  backend "azurerm" {
    resource_group_name  = "<your-state-resource-group>"   # ⚠️ your state RG (e.g. rg-tfstate-landingzone)
    storage_account_name = "<your-state-storage-account>"  # ⚠️ your state storage account (e.g. sttflzstate...)
    container_name       = "tfstate"                       # ⚠️ confirm: az storage container list
    key                  = "private-storage-validation.tfstate"
  }
}
```

> **Important:** every value inside `backend "azurerm" {}` must be a **literal string** — `var.x` and `local.x` are not allowed. Terraform needs to know where state lives before it has loaded any variables, so interpolation isn't supported in this one block. The whole block must also sit inside a `terraform { }` wrapper — a bare `backend "azurerm" {}` at the top level won't parse. If you did Step 1B, get the real account name with `cd bootstrap && terraform output`.

> Note: the `azurerm` backend locks state using a native blob lease on this account — no separate lock table needed (unlike AWS pairing S3 with DynamoDB).

---

## Step 5 — Declare root variables and shared tags

**What:** The central place for configurable values, plus a `locals` block for tags applied to everything.

**Why:** hardcoding a region string across several module calls means changing it later needs several edits. One variable, referenced everywhere, changes in one place. `common_tags` does the same for tagging — every resource carries the same `project`/`environment`/`managed_by` tags without repeating them.

`variables.tf`

```
variable "location" {
  type    = string
  default = "<your-region>"   # e.g. eastus, uksouth, centralindia
}

variable "resource_group_name" {
  type    = string
  default = "rg-private-storage-validation"
}
```

`locals.tf`

```
locals {
  common_tags = {
    project     = "private-storage-validation"
    environment = "dev"
    managed_by  = "terraform"
  }
}
```

---

## Step 6 — Build the networking module

**What:** The minimum network the private endpoint needs — a hub VNet, a spoke VNet, one subnet (`snet-pe`) for the endpoint, hub↔spoke peering, and an NSG.

**Why it's trimmed:** the landing-zone build has more subnets (workload, Bastion) and their NSG rules, all there to support a VM and Bastion. This run has neither, so it creates only `snet-pe` (10.20.2.0/24) — the subnet the private endpoint's NIC lands in — and nothing that costs money to idle.

**Why each piece exists:**

- **Hub + spoke VNets** — private address ranges nothing outside can reach unless explicitly allowed. The hub/spoke shape mirrors the real topology so the pattern is representative, even trimmed.
- **`snet-pe` with `private_endpoint_network_policies = "Disabled"`** — a private endpoint can only be placed in a subnet that has this set to `Disabled`. Leave it on and the apply fails when it tries to create the endpoint.
- **Peering, both directions** — VNets ignore each other by default; peering is a one-way permission, so hub→spoke and spoke→hub are two resources.
- **NSG** — locks the subnet to VNet-internal traffic (allow intra-VNet, deny the rest inbound), evaluated by priority, lowest number first.

**Write `variables.tf` first, then `main.tf`.** VS Code's Terraform extension flags every `var.xxx` in `main.tf` with a red "no declaration found" squiggle until the declaration exists — declaring first avoids that in every module below.

**Note on `resource_group_name`'s default below:** normally a module variable with no obvious fallback is left required (no `default`), so a missing value fails loudly instead of guessing wrong. Here the default is set to match the root's own default (`rg-private-storage-validation`), since this project only ever has one resource group. Step 8 still always passes the real value explicitly (`azurerm_resource_group.main.name`) — the default is just a safety net, not something this build actually relies on.

`modules/networking/variables.tf`

```
variable "location" {
  type        = string
  default     = "<your-region>"
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  default     = "rg-private-storage-validation"
  description = "Resource group for all networking resources"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common resource tags"
}
```

`modules/networking/main.tf`

```
# Hub VNet
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.10.0.0/16"]
  tags                = var.tags
}

# Spoke VNet
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

# Spoke subnet: private endpoints. Policies MUST be Disabled to host a PE.
resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = ["10.20.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}

# Bidirectional peering: hub <-> spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-spoke"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-spoke-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

# NSG on the PE subnet: allow intra-VNet, deny the rest inbound
resource "azurerm_network_security_group" "pe" {
  name                = "nsg-snet-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}
```

`modules/networking/outputs.tf` — this is the wiring the storage module depends on. `spoke_vnet_id` feeds the private DNS zone link; `pe_subnet_id` is where the endpoint lands. Step 8 passes both into the storage module.

```
output "spoke_vnet_id" {
  value = azurerm_virtual_network.spoke.id
}

output "spoke_vnet_name" {
  value = azurerm_virtual_network.spoke.name
}

output "pe_subnet_id" {
  value = azurerm_subnet.pe.id
}
```

---

## Step 7 — Build the private-storage module

**What:** The storage account and the three things that make it reachable *only* privately.

**Why each piece exists — and why all four are needed:**

- **Storage account with `public_network_access_enabled = false`** — this is the lockdown itself. On its own, though, the account is now unreachable by anything, including your VNet.
- **Private DNS zone `privatelink.blob.core.windows.net`** — when public access is off, the account's public DNS name needs to resolve to a *private* IP instead. This zone holds that private record.
- **VNet link** — a DNS zone does nothing until it's linked to a network. This link is what makes lookups from inside the spoke resolve against the private zone.
- **Private endpoint (+ DNS zone group)** — the actual NIC in `snet-pe` that gives the account a private IP, and the zone group that auto-creates the matching A record. Remove any one of these four and the private-access pattern breaks.

`modules/private-storage/variables.tf` — note `spoke_vnet_id` and `pe_subnet_id`: declaring them here is what lets the root hand the networking module's outputs into this module.

```
variable "resource_group_name" {
  type        = string
  default     = "rg-private-storage-validation"
  description = "Resource group for storage + private endpoint"
}

variable "location" {
  type        = string
  default     = "<your-region>"
  description = "Azure region"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name (lowercase, no hyphens, 3-24 chars)"
}

variable "spoke_vnet_id" {
  type        = string
  description = "Spoke VNet resource ID for the private DNS zone link"
}

variable "pe_subnet_id" {
  type        = string
  description = "snet-pe subnet resource ID where the private endpoint NIC is placed"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common resource tags"
}
```

`modules/private-storage/main.tf`

```
# Storage account — public network access fully disabled
resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  public_network_access_enabled   = false
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Private DNS zone for blob endpoints
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link the DNS zone to the spoke VNet
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob-spoke"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = var.spoke_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# Private endpoint into snet-pe
resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.storage_account_name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-${var.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # Auto-creates the A record in the linked private DNS zone
  private_dns_zone_group {
    name                 = "dns-zone-group-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}
```

`modules/private-storage/outputs.tf` — surfaces what you'll check in Step 10. The private endpoint IP should be a `10.20.2.x` address (inside `snet-pe`).

```
output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "private_endpoint_ip" {
  value       = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
  description = "Private IP assigned to the blob endpoint inside snet-pe"
}

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.blob.id
}
```

> **Gotcha:** if you later add an `azurerm_storage_container` to this module, it takes `storage_account_id` on the v5 provider, not `storage_account_name` — same breaking change as the bootstrap.

---

## Step 8 — Wire the root config: call both modules

**What:** Create the resource group, generate the unique storage suffix, then call both modules — passing the networking module's outputs straight into the storage module's inputs.

**Why this step exists on its own:** the two modules are just reusable code sitting in `modules/` until something calls them with real values. This is that call, and it's where the dependency is declared: `pe_subnet_id = module.networking.pe_subnet_id` tells Terraform to build the network first, then the storage — it reads that ordering from the reference automatically.

`main.tf`

```
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Unique suffix so the storage account name is globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

module "networking" {
  source              = "./modules/networking"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

module "private_storage" {
  source               = "./modules/private-storage"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  storage_account_name = "stpriv${random_string.suffix.result}"
  spoke_vnet_id        = module.networking.spoke_vnet_id
  pe_subnet_id         = module.networking.pe_subnet_id
  tags                 = local.common_tags
}
```

Notice `module.networking.spoke_vnet_id` and `.pe_subnet_id` — those are exactly the outputs defined in Step 6's `outputs.tf`. This is how one module's result flows into the next module's input. If you ever wanted the full stack, the VM/Bastion modules would be added here too; leaving them out is what keeps this run cheap.

`outputs.tf` — re-exposes the module's values at the top level so `terraform output` and the Step 10 checks (which call `terraform output -raw ...`) can read them without digging into the module.

```
output "storage_account_name" {
  value = module.private_storage.storage_account_name
}

output "private_endpoint_ip" {
  value = module.private_storage.private_endpoint_ip
}

output "spoke_vnet_name" {
  value = module.networking.spoke_vnet_name
}
```

---

## Step 9 — Deploy

**What:** Build everything.

**Why the sequence:** `validate` catches syntax errors cheaply, `plan -out` shows exactly what will change *before* anything is touched, and applying the saved plan file guarantees you apply what you reviewed — the core Terraform safety habit.

```
terraform init
terraform validate      # expect: Success! The configuration is valid.
terraform plan -out=tfplan
```

Skim the plan and confirm it creates **only**: 1 resource group, hub + spoke VNets, the `snet-pe` subnet, 2 peerings, 1 NSG + association, the storage account, private endpoint, private DNS zone and VNet link, and 1 `random_string`. There should be **no** VM, **no** Bastion, **no** public IP.

```
terraform apply tfplan
terraform output
```

---

## Step 10 — Run the proof tests

Each test answers a specific "how do you know?" a reviewer would ask. All of these work **without a VM** — both the CLI command and the equivalent portal path are given below, since a portal screenshot is often clearer documentation than a terminal output.

**Test 1 — Public network access is disabled**

CLI:
```
az storage account show \
  --name $(terraform output -raw storage_account_name) \
  --resource-group rg-private-storage-validation \
  --query "publicNetworkAccess" -o tsv
# Expect: Disabled
```

Portal: **Storage account → Networking** (left nav, under Security + networking). Confirm **Public network access: Disabled**. The same blade also shows **Private endpoint connections: 1** — a free bonus confirmation for Test 2 without an extra click.

**Test 2 — Private endpoint is approved**

CLI:
```
SA=$(terraform output -raw storage_account_name)
az network private-endpoint show \
  --name "pe-${SA}-blob" \
  --resource-group rg-private-storage-validation \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv
# Expect: Approved
```

Portal: **Resource group → `pe-<storage_account_name>-blob` (the Private Endpoint resource) → Overview**. Confirm **Connection status: Approved**. You can also open **DNS configuration** in the left nav of the same resource to see the private IP it was assigned in `snet-pe`.

**Test 3 — The private DNS A record was auto-created**

CLI:
```
az network private-dns record-set a list \
  --resource-group rg-private-storage-validation \
  --zone-name "privatelink.blob.core.windows.net" \
  --query "[].{name:name, ip:aRecords[0].ipv4Address}" -o table
# Expect: an A record pointing at a 10.20.2.x address
```

Portal: **Resource group → `privatelink.blob.core.windows.net` (the Private DNS zone) → Overview**, then click the record set with your storage account name under **Recordsets**. Confirm it's type **A** and the **IP Address** column shows a `10.20.2.x` address.

Proves the endpoint's DNS zone group did its job — the storage name now resolves to a private IP inside `snet-pe`.

**Test 4 — Public access is blocked from outside the VNet**

CLI:
```
SA=$(terraform output -raw storage_account_name)
curl -s -o /dev/null -w "%{http_code}\n" "https://${SA}.blob.core.windows.net/?comp=list"
# Expect: 403 — reachable name, but public access denied
```

Portal: **Storage account → Containers** (under Data storage). Attempting to open the containers list from the portal UI itself — while signed in from outside the VNet — surfaces an **access-denied / "This request is not authorized"** banner, since the portal's own management calls go over the same public endpoint you just locked down. This is a slightly less clean proof than the `curl` 403 (the portal has its own retry/caching behaviour), so keep the CLI version as your primary evidence for this one.

**Test 5 — Idempotency**

```
terraform plan
# Expect: No changes. Your infrastructure matches the configuration.
```

If it isn't clean, something in the code produces a different result each run — a real bug, not noise. There's no portal equivalent for this one — idempotency is a Terraform-state concept, not something the resource's portal blade can show you.

> **Optional internal-resolution test:** to prove `nslookup` resolves to the private IP *from inside* the VNet, spin up a temporary **B1s** Linux VM (no public IP) in the spoke, run the lookup, then delete just that VM — a few pence for an hour, far cheaper than leaving Bastion running.


---

## Step 11 — What this proves, end to end

- The storage account refuses public network access — verified directly
- The private endpoint exists and is Approved
- DNS auto-resolves the storage name to a private `10.20.2.x` address
- From outside the VNet the account is not publicly usable (403)
- A second `plan` shows no drift

---

## Step 12 — Teardown

**What:** Remove everything that costs money, without destroying a shared state backend.

**Why the split:** the networking + storage `destroy` is safe to run fully. But if you **reused** a backend in Step 1A, that account is shared — destroying it would break other projects. So only delete this project's state *file*, not the account.

```
# From the project root — removes networking + storage
terraform destroy
```

Then, depending on Step 1:

- **Reused an existing backend (1A):** do **not** destroy it. Optionally delete just this project's state blob:
  ```
  az storage blob delete \
    --account-name <your-existing-tfstate-sa> \
    --container-name tfstate \
    --name private-storage-validation.tfstate \
    --auth-mode login
  ```
- **Bootstrapped a fresh backend (1B):** tear it down too:
  ```
  cd bootstrap
  terraform destroy
  cd ..
  ```

Confirm nothing is left billing:

```
az group list --query "[?starts_with(name, 'rg-')].name" -o table
```

> **Cost note:** with the VM and Bastion skipped, the only meaningful cost is the storage account(s) — LRS/Standard, negligible while idle. Private endpoints, private DNS zones, VNets and NSGs are free or fractions of a rupee idle. The `destroy` above brings you back to zero.
