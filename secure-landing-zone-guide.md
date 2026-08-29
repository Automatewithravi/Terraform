# Part 1: Secure Hub-and-Spoke Landing Zone — Build Guide

Region: Central India (`centralindia`) · Terraform 1.15.8 · azurerm ~>5.1

Work through this top to bottom. Each step has: **what it is**, **why it exists**, then the exact code/commands. Don't skip the "why" — it's what you'll be asked about in an interview or need for your blog write-up.

**Every code block in this guide can be copied exactly as written, except these 3 spots** — marked again inline where they occur, but listed here so you know what to expect before starting:

| # | Where | What to enter | When you'll have it |
|---|---|---|---|
| 1 | `environments/dev/terraform.tfvars` → `subscription_id` | Output of `az account show --query id -o tsv` | Anytime — do it in Step 6 |
| 2 | `environments/dev/terraform.tfvars` → `ssh_public_key` | Output of `cat ~/.ssh/landingzone_dev.pub` | After Step 0 |
| 3 | `environments/dev/backend.tf` → `storage_account_name` | The real storage account name from Step 1's `terraform output` | Only after Step 1's `apply` completes |

Nothing else in the guide needs a substituted value — resource names, VM size, region, and every module's variables are fixed defaults.

---

## Step 0 — Prerequisites

**What:** Confirm your tools and identity are ready before writing any Terraform.

**Why:** Terraform needs to know *which* Azure subscription to act on, and your VM will need an SSH key pair instead of a password (passwords on VMs are a common audit finding).

```bash
az login
az account set --subscription "<your-subscription-id>"
az account show --output table   # confirm the right subscription is active

terraform version                # confirm 1.15.8

ssh-keygen -t ed25519 -f ~/.ssh/landingzone_dev -C "landingzone-dev"
```

---

## Step 1 — Bootstrap the remote state backend

**What:** A one-time, separate Terraform config that creates a Storage Account purely to hold Terraform's *state file* (its record of what infrastructure already exists).

**Why:** Terraform state can't live on your laptop long-term — it can't be shared, gets lost, and doesn't support locking (which stops two runs from colliding). But the storage account that *holds* state is itself infrastructure, and Terraform can't store its state in a bucket that doesn't exist yet. So this step runs once, with **local** state, to create that bucket. After this, you never touch it again.

**Folder:** `bootstrap/remote-state/`

`versions.tf`
```hcl
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

`main.tf`
```hcl
resource "azurerm_resource_group" "state" {
  name     = "rg-tfstate-landingzone"
  location = "centralindia"
}

resource "azurerm_storage_account" "state" {
  name                     = "sttflzstate${random_string.suffix.result}"
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
  name                   = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
```

**Run it:**
```bash
cd bootstrap/remote-state
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

**Checkpoint:** note the storage account name from the output (e.g. `sttflzstateab12cd`) — you'll need it in Step 3.

> **Gotchas hit while building this (keep for your "lessons learned" section):**
> - Double-check the provider name is spelled `random`, not `randon` — a typo here produces a confusing "provider registry does not have a provider named..." error rather than an obvious spelling complaint.
> - `azurerm_storage_container` in the v5 provider line takes `storage_account_id`, not `storage_account_name` (shown correctly above). This is a real v4→v5 breaking change — several storage sub-resources (`azurerm_storage_blob`, `azurerm_storage_share`, `azurerm_storage_queue`) made the same switch, so use `storage_account_id` from the start when you build the private storage account in Part 2.

---

## Step 2 — Scaffold the repo

**What:** The folder layout everything else will live in.

**Why:** Modules (reusable network/VM building blocks) are kept separate from environments (dev/prod configs that *call* those modules with different values). This is what lets you reuse the same hub-network code for both dev and prod without copy-pasting it.

```
azure-secure-landing-zone/
├── bootstrap/remote-state/          ← done in Step 1
├── environments/dev/
│   ├── versions.tf
│   ├── backend.tf
│   ├── providers.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── terraform.tfvars
│   └── outputs.tf
├── modules/
│   ├── resource-group/
│   ├── hub-network/
│   ├── spoke-network/
│   └── virtual-machine/
└── README.md
```

Create the empty folders now; you'll fill them in over the next steps.

> **Note on Git:** this guide builds and tests the Azure infrastructure with plain local folders — no Git required for any of that. Version control and pushing to a repo are separate steps, outside the scope of this guide.

---

## Step 3 — Pin Terraform and the provider version

**What:** Declare which Terraform version and which `azurerm` plugin version your code is built for.

**Why:** Terraform itself doesn't know anything about Azure — the `azurerm` provider is a plugin that translates your `.tf` code into real Azure API calls. Pinning its version is exactly like pinning a `package.json` or `requirements.txt` — it stops a future provider update from silently changing how your code behaves.

`environments/dev/versions.tf`
```hcl
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

## Step 4 — Point this environment at the remote state you created

**What:** Tell this `dev` config to store *its* state file in the storage account from Step 1.

**Why:** This is what makes Terraform state shareable and lockable, instead of sitting on your laptop.

`environments/dev/backend.tf`
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-landingzone"
    storage_account_name = "sttflzstate<paste-your-suffix-here>"   # ⚠️ PLACEHOLDER — replace before running
    container_name        = "tfstate"
    key                    = "dev.terraform.tfstate"
  }
}
```

> Note: the `azurerm` backend locks state using a **native blob lease** on this storage account — you don't need a separate locking resource (unlike AWS, which pairs S3 with DynamoDB for this).

> **Important:** every value inside `backend "azurerm" {}` must be a **literal string** — `var.something` and `local.something` are not allowed here. Terraform needs to know where state lives before it has loaded any variables, so interpolation isn't supported in this one block. Get the real storage account name with:
> ```bash
> cd bootstrap/remote-state
> terraform output
> ```
> and paste that exact string in place of `sttflzstate<paste-your-suffix-here>` above.

---

## Step 5 — Configure the Azure provider

**What:** Tell Terraform *how* to authenticate and which subscription to act on.

**Why:** This is the one place in the whole repo where "how do we talk to Azure" is defined. Modules never repeat this — if every module configured its own provider, different modules could end up authenticating differently or hitting different subscriptions, which is exactly the kind of inconsistency you don't want in something meant to look production-minded.

`environments/dev/providers.tf`
```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  subscription_id = var.subscription_id
}
```

`features {}` is mandatory even when empty — the provider won't initialize without it. The `prevent_deletion_if_contains_resources` flag is a small but good talking point: it stops someone (including future-you) from accidentally deleting a resource group that still has things in it.

---

## Step 6 — Declare your variables and shared tags

**What:** Central place for every configurable value (region, VM size, whether Bastion is deployed, etc.) and a `locals` block for tags applied to everything.

**Why:** Hardcoding values like `"centralindia"` inside five different module calls means changing region later requires editing five files. One variable, referenced everywhere, means changing it in one place changes it everywhere. `locals.common_tags` is the same idea for tagging — every resource gets the same `project`/`environment`/`managed_by` tags without repeating them.

`environments/dev/locals.tf`
```hcl
locals {
  env    = "dev"
  prefix = "lz"
  common_tags = {
    project     = "secure-landing-zone"
    environment = local.env
    location    = var.location
    managed_by  = "terraform"
  }
}
```

`environments/dev/variables.tf`
```hcl
variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "deploy_bastion" {
  type    = bool
  default = false
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "hub_address_space" {
  type    = string
  default = "10.10.0.0/16"
  validation {
    condition     = can(cidrhost(var.hub_address_space, 0))
    error_message = "hub_address_space must be a valid CIDR block."
  }
}
```

The `validation` block is what stops `terraform apply` at the door if someone (including future-you) typos the CIDR — it fails fast with a clear message instead of Azure rejecting it deep into the apply.

**Now create the real `terraform.tfvars` file** — this is where you supply your actual values for the two variables above that have no `default` (`subscription_id`, `ssh_public_key`). Terraform will refuse to proceed without these, so do this now rather than waiting for it to prompt you later.

Get your subscription ID:
```bash
az account show --query id -o tsv
```

Get your SSH public key exactly as generated in Step 0:
```bash
cat ~/.ssh/landingzone_dev.pub
```

`environments/dev/terraform.tfvars` (real values — this file is gitignored, never commit it)
```hcl
subscription_id = "<paste-the-output-of-az-account-show-here>"
ssh_public_key  = "<paste-the-entire-output-of-cat-.pub-here>"
```

Both values above are placeholders you must replace — everything else in this guide's code blocks can be copied exactly as written.

---

## Step 7 — Build the resource group module

**What:** The container every other resource lives inside.

**Why it's a module, not inline code:** keeping even something this small as a module means naming and tagging stay consistent if you ever add a second resource group (e.g. for prod).

**Write `variables.tf` first, then `main.tf`.** VS Code's Terraform extension checks `var.xxx` references live as you type — if `main.tf` exists before `variables.tf`, every variable reference shows a red "no declaration found" squiggle until the declaration catches up. Writing the declarations first avoids that entirely, in every module below.

**Why every module needs its own `variables.tf`:** a module is an isolated scope — it never inherits variables from `environments/dev`, even though that folder is right next to it. Whatever `var.xxx` a module's `main.tf` will reference, that same module's own `variables.tf` must declare first.

`modules/resource-group/variables.tf`
```hcl
variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

`modules/resource-group/main.tf`
```hcl
resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = var.tags
}
```

`modules/resource-group/outputs.tf` — needed because Step 11's peering resources and other modules reference this resource group's name:
```hcl
output "name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}
```

---

## Step 8 — Build the hub network module

**What:** The shared/central network — holds Bastion (your secure remote-access path) plus space for future shared services.

**Why each piece exists:**
- **VNet `10.10.0.0/16`** — a private address range; nothing outside can reach it unless you explicitly allow it.
- **Bastion subnet + host** — since your VM will have no public IP, you need *some* way to SSH into it. Azure Bastion is Microsoft's managed jump-box: you connect via the Azure Portal over HTTPS, and it relays you privately into the VNet. It must sit in its own dedicated subnet named exactly `AzureBastionSubnet` — Azure requires that literal name.
- **`count = var.deploy_bastion ? 1 : 0`** — Bastion bills hourly just for existing. This pattern means "only build it if the flag says yes," so you can switch it on for a testing session and off again without touching anything else.

`modules/hub-network/variables.tf`
```hcl
variable "env" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "deploy_bastion" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

`modules/hub-network/main.tf`
```hcl
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.env}"
  address_space       = ["10.10.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.0.0/26"]
}

resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "pip-bastion-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "this" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "bas-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
```

`modules/hub-network/outputs.tf` — Step 11's peering needs these:
```hcl
output "vnet_name" {
  value = azurerm_virtual_network.hub.name
}

output "vnet_id" {
  value = azurerm_virtual_network.hub.id
}
```

**Before continuing, check whether Azure already has Network Watcher in this region** (it auto-creates one the first time you deploy a VNet in a region):
```bash
az network watcher list --query "[?location=='centralindia']" -o table
```
If nothing shows yet, that's expected before your first apply — it'll appear afterward.

---

## Step 9 — Build the spoke network module

**What:** The application network — holds your workload VM, isolated from the hub except through the rules you explicitly allow.

**Why each piece exists:**
- **Two subnets, not one** — the workload subnet holds your VM now; the private-endpoint subnet is reserved for Part 2's storage private endpoint. Separating them keeps NSG rules clean and matches how real landing zones are structured.
- **NSG (Network Security Group)** — a firewall attached to the subnet. Rules are evaluated by **priority, lowest number first**. Your rule at priority 100 allows SSH only from the Bastion subnet's address range; priority 4096 denies everything else inbound. Anything that isn't Bastion hitting this VM gets caught by your explicit deny — and Azure can name that denial when asked (this is your Test 6 later).

`modules/spoke-network/variables.tf`
```hcl
variable "env" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

`modules/spoke-network/main.tf`
```hcl
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-app-${var.env}"
  address_space       = ["10.20.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-workload"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.20.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-SSH-From-Bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.10.0.0/26"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
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

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}
```

`modules/spoke-network/outputs.tf` — Step 11's peering and Step 13's VM module call (needs the workload subnet ID) both need these:
```hcl
output "vnet_name" {
  value = azurerm_virtual_network.spoke.name
}

output "vnet_id" {
  value = azurerm_virtual_network.spoke.id
}

output "workload_subnet_id" {
  value = azurerm_subnet.workload.id
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}
```

---

## Step 10 — Wire the root config: call each module

**What:** Actually invoke the modules you built in Steps 7–9 from `environments/dev/main.tf`, passing in the real values (`var.location`, `local.common_tags`, etc.) that flow down into each module's own variables.

**Why this step exists on its own:** every module so far (`resource-group`, `hub-network`, `spoke-network`) is just reusable code sitting in `modules/` until something actually calls it with real values. This is that call.

`environments/dev/main.tf`
```hcl
module "resource_group" {
  source   = "../../modules/resource-group"
  name     = "rg-landingzone-${local.env}"
  location = var.location
  tags     = local.common_tags
}

module "hub_network" {
  source               = "../../modules/hub-network"
  env                  = local.env
  location             = var.location
  resource_group_name  = module.resource_group.name
  deploy_bastion       = var.deploy_bastion
  tags                 = local.common_tags
}

module "spoke_network" {
  source               = "../../modules/spoke-network"
  env                  = local.env
  location             = var.location
  resource_group_name  = module.resource_group.name
  tags                 = local.common_tags
}
```

Notice the pattern: `module.resource_group.name` in the hub/spoke calls is exactly the output you defined in Step 7's `outputs.tf` — this is how one module's result flows into the next module's input, all wired together at the root level.

**Note:** the `virtual_machine` module isn't called here yet — it doesn't exist until Step 12 builds it. Its module call comes in Step 13, once there's actually something to call.

---

## Step 11 — Peer the hub and spoke together

**What:** The explicit "permission grant" that lets traffic flow between the two VNets.

**Why you need it twice:** VNets know nothing about each other by default, even in the same subscription. Peering is a one-directional permission — hub→spoke and spoke→hub are two separate resources, even though they reference the same pair of networks. Both are needed for two-way communication.

**Why this lives in `environments/dev`, not inside a module:** it references outputs from *both* the hub and spoke modules, so it belongs at the level that calls both of them. Add this to the same `environments/dev/main.tf` file, below the module blocks from Step 10.

```hcl
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                       = "peer-hub-to-spoke"
  resource_group_name       = module.resource_group.name
  virtual_network_name      = module.hub_network.vnet_name
  remote_virtual_network_id = module.spoke_network.vnet_id
  allow_forwarded_traffic   = false
  allow_gateway_transit     = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                       = "peer-spoke-to-hub"
  resource_group_name       = module.resource_group.name
  virtual_network_name      = module.spoke_network.vnet_name
  remote_virtual_network_id = module.hub_network.vnet_id
  allow_forwarded_traffic   = false
  use_remote_gateways       = false
}
```

`allow_forwarded_traffic` and `use_remote_gateways` are deliberately `false` — they'd only matter if you added a firewall appliance or VPN gateway in the hub, which you're intentionally not doing in this version.

---

## Step 12 — Build the VM module (no public IP, by construction)

**What:** The one workload VM, reachable only through Bastion.

**Why "no public IP" is structural, not just a rule:** notice the network interface's `ip_configuration` block never references a public IP resource. In Azure, a VM is only internet-reachable if its NIC is explicitly wired to one. By simply never creating that link, the VM is unreachable from the internet by construction — there's no rule to misconfigure or accidentally delete later, unlike a firewall-based block.

**Why SSH key, not password:** even the one thing allowed to reach it (Bastion) still needs your private key — removing password guessing as an attack path entirely.

`modules/virtual-machine/variables.tf`
```hcl
variable "env" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "admin_username" {
  type    = string
  default = "azureadmin"
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}
```

`modules/virtual-machine/main.tf`
```hcl
resource "azurerm_network_interface" "vm" {
  name                = "nic-app01-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    # deliberately: no public_ip_address_id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                   = "vm-app01-${var.env}"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
```

Before locking in `vm_size`, confirm it's actually offered in Central India:
```bash
az vm list-skus --location centralindia --output table
```

---

## Step 13 — Call the VM module from root

**What:** Add the `virtual_machine` module call to `environments/dev/main.tf`, below the module blocks and peering resources from Steps 10–11.

**Why this is its own step:** in Step 10 you couldn't call this module yet — it didn't exist until Step 12 just built it. This is the missing link that actually wires the VM into the rest of the config; without it, `terraform plan` in Step 14 would build the network and stop, since nothing tells Terraform to create the VM at all.

Add this to the end of `environments/dev/main.tf`:
```hcl
module "virtual_machine" {
  source               = "../../modules/virtual-machine"
  env                  = local.env
  location             = var.location
  resource_group_name  = module.resource_group.name
  subnet_id            = module.spoke_network.workload_subnet_id
  vm_size              = var.vm_size
  admin_username       = "azureadmin"
  ssh_public_key       = var.ssh_public_key
}
```

`subnet_id = module.spoke_network.workload_subnet_id` is exactly the output you defined in Step 9 — this is the VM landing in the workload subnet, not the private-endpoint one.

At this point, `environments/dev/main.tf` contains, top to bottom: the three module blocks from Step 10, the two peering resources from Step 11, and this VM module block — one file, built up across three steps.

---

## Step 14 — First apply

**What:** Actually build everything.

**Why the sequence matters:** `fmt` fixes style, `validate` catches syntax errors cheaply, `plan` shows you exactly what will change *before* anything is touched — this is the core Terraform safety habit.

```bash
cd environments/dev
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Step 15 — Turn Bastion on only while testing

**What:** Flip the cost-bearing resource on, test, flip it off.

**Why:** Bastion bills hourly regardless of use. Keeping it off by default and switching it on only for a testing session is your cost-control mechanism.

```bash
terraform apply -var="deploy_bastion=true"
# run your tests, capture screenshots
terraform apply -var="deploy_bastion=false"
```

---

## Step 16 — Run the proof tests

Each test answers a specific "how do you know?" question a reviewer would ask.

**Test 1 — VM has no public IP**
```bash
az vm list-ip-addresses -g <rg> -n vm-app01-dev -o table
```
Confirms the earlier structural claim, not just a description of intent.

**Test 2 — Hub and spoke actually communicate**
```bash
az network vnet peering list -g <rg> --vnet-name vnet-hub-dev -o table
az network nic show-effective-route-table -g <rg> -n nic-app01-dev -o table
```
A peering resource existing isn't proof by itself — it can be misconfigured or disconnected. The effective route table proves the hub's address range is actually reachable from the spoke's NIC.

**Test 6 — Unauthorised connection is blocked**
```bash
az network watcher test-connectivity \
  --source-resource vm-app01-dev \
  --dest-address 10.20.1.4 --dest-port 3389 \
  --protocol Tcp
```
Proves your "deny by default" NSG rule isn't just sitting there unused — Azure's own diagnostic tool will name the specific rule that blocked it.

**Test 7 — Idempotency**
```bash
terraform plan
```
Should say "No changes." If it doesn't, something in your code produces a different result each run — a sign of a real bug, not just noise.

**Test 8 — A variable change produces only the expected plan**
Change `vm_size` in `terraform.tfvars`, then:
```bash
terraform plan
```
Confirm only the VM resource is affected — proves you understand Terraform's dependency graph, not just that commands run.

**Test 9 — Clean destroy**
```bash
terraform destroy
```
Confirms there's no manual cleanup step and nothing gets left behind racking up cost.

---

## Step 17 — What this proves, end to end

- VM has no public IP — verified directly
- Peering is connected and actually routable in both directions
- The NSG deny rule blocks unauthorised traffic, not just exists on paper
- A second `plan` shows no drift
- A variable change produces a correctly scoped diff
- `destroy` removes everything cleanly, in the right order

---

## Before committing to version control

Two files worth having in place regardless of how you push this to a repo, since Terraform generates local files that should never be committed: `terraform.tfvars` (your subscription ID, SSH key), `.terraform/`, and any `.tfstate` left over from the bootstrap step.

`azure-secure-landing-zone/.gitignore`
```
# Terraform state — never commit; lives in the remote backend instead
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# Variable files — may contain subscription IDs, keys; commit a .example instead
*.tfvars
*.tfvars.json
!*.tfvars.example

# Crash logs / override files
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# SSH keys, if you ever generate them inside the repo folder by mistake
*.pem
id_*
```

A sanitized example of your variables file — safe to commit, documents the shape without real values:

`environments/dev/terraform.tfvars.example`
```hcl
subscription_id = "<your-azure-subscription-id>"
ssh_public_key  = "<contents-of-your-.pub-file>"
```

Before adding anything else to version control, confirm your real `terraform.tfvars` and any `.tfstate` files are correctly ignored — they should never appear in a status check once `.gitignore` is in place.

---


