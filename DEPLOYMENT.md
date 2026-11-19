# Australia East deployment (AzureGoat exception)

This lab defaults all regional resources, including the Cosmos DB replica, to `australiaeast`. This is an explicit exception for AzureGoat; the separate firewall training lab remains in East US.

On 2026-11-19 the tested paid subscription rejected actual Y1 and B1 plan creation in East US with effective quota 0, despite a SKU quota API displaying 30. A Y1 plan was successfully created in Australia East. This is a subscription-specific observation, not a claim that East US is unavailable for all Azure customers.

The lab deliberately retains the upstream application vulnerabilities, public storage containers, exposed lab source package, sample credentials/keys, and resource-group-scoped privilege-escalation path. Use a dedicated lab resource group and subscription without production data. The deployment improvements below do not turn AzureGoat into a production application.

## Requirements

- Terraform >= 1.7, Azure CLI logged into the intended subscription.
- Local Python >= 3.10, plus `scripts/requirements.txt` installed in a virtual environment.
- Permission to create resources and assign roles within the lab resource group.
- Available Linux Y1 App Service quota in Australia East, at least 2 regional vCPUs and 2 StandardDsv6Family vCPUs, and one Standard public IPv4 address.
- The default VM is `Standard_D2s_v6` with Ubuntu 24.04 LTS. D2s_v7 was absent from the tested Australia East SKU list. Override `vm_size` if your subscription supports a different SKU.

Free Trial subscriptions may have a Y1 limit of zero. A valid Terraform plan is not proof that quota or regional capacity permits deployment. Do not delete unrelated resources or switch subscriptions silently to work around a quota failure.

## New deployment

Do **not** create the resource group manually: Terraform now manages it. If the intended group already exists, choose a new name, or review its contents and explicitly import it before applying.

Linux / Cloud Shell:

```bash
git clone https://github.com/gasbugs/AzureGoat.git
cd AzureGoat
az login
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements.txt
cp terraform.tfvars.example terraform.tfvars
```

Windows PowerShell:

```powershell
git clone https://github.com/gasbugs/AzureGoat.git
cd AzureGoat
az login
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r scripts/requirements.txt
Copy-Item terraform.tfvars.example terraform.tfvars
```

Set `subscription_id` explicitly in `terraform.tfvars`. On Windows set `python_executable` to the absolute forward-slash path to `.venv/Scripts/python.exe`; on Linux use the absolute path to `.venv/bin/python` (or the supplied relative path).

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=azuregoat.tfplan'
terraform apply azuregoat.tfplan
terraform output Target_URL
terraform output API_URL
```

Creation and remote Function builds can take several minutes. Terraform installs the backend Python dependencies through Azure's remote build, not the old checked-in Python 3.9 wheels. The frontend uses Functions 4 and Node.js 22; the backend uses Functions 4 and Python 3.11. [Supported runtimes](https://learn.microsoft.com/en-us/azure/azure-functions/functions-versions)

## What changed

- One location variable controls the resource group, Cosmos account/replica, storage, Functions, VM and Automation resources.
- AzureRM 4 resources, locked provider versions, Standard/Static public IP, Ubuntu 24.04 and D2s_v6 defaults replace obsolete deployment settings.
- HTTP trigger catch-all routes omit a leading slash so requests reach the app. The generated HTML omits the upstream missing local font stylesheet; the existing Google Fonts reference supplies the font.
- Functions 4 remote builds install `azure-functions` and the backend requirements. The intentionally vulnerable application dependency versions remain part of the lab.
- Deployment rendering uses portable Python instead of Bash `sed`, and writes only into ignored `.build/`. Tracked source files and placeholder fixtures remain reusable.
- Cosmos database/containers are managed by Terraform. Initial records are inserted without reading `terraform.tfstate`, printing keys, or overwriting learner-modified records on a later apply.
- ZIP outputs are outside ZIP input directories and their paths include the source hash, so AzureRM redeploys changed code rather than only updating app settings. Runtime packages do not expire after a 10-day SAS token.
- Storage asset URLs and VM SSH configuration are rendered before upload. Changes to source files trigger a new build and deployment.
- VM provisioning fails on errors, uses noninteractive installation and retries downloads. The sample Justin SSH key remains an intentional lab path.
- The Automation runbook uses ordinary PowerShell with a user-assigned identity, and role assignments stay within the lab resource group.

## Verification

```powershell
python -m unittest discover -s scripts -p 'test_*.py' -v
python scripts/smoke_test.py --frontend (terraform output -raw Target_URL) --api (terraform output -raw API_URL)
terraform plan -detailed-exitcode
```

The smoke test checks live HTML, JS/CSS, seeded posts/images and registration/login. It creates one uniquely named `deployment-check-...@example.invalid` user in the lab and never prints its password or token.

The local test verifies that repeated preparation does not mutate source files, excludes old runtime wheels, updates asset/API/VM URLs, and preserves the intended lab package data. A successful local test does not certify a live deployment.

For live acceptance, open `Target_URL`, confirm the JS/CSS assets load, load the blog list, and exercise registration/login. Verify the VM extension succeeds and the `Get-AzureVM` runbook can execute with its managed identity. Record actual results separately; do not equate successful resource creation with working application behavior.

## State and cleanup

This update changes Terraform resource types and addresses from the legacy configuration. It is intended for a **fresh deployment**. Do not apply it over a legacy state without a reviewed import/state migration plan.

Keep `.build/`, `.venv/`, `.tfvars`, plans and state local; `.build/` and state contain lab credentials. The original repository already contains sample lab keys: do not substitute personal keys into those public fixtures.

Use the same local working directory and state to remove the lab:

```powershell
terraform plan -destroy
terraform destroy
```

VMs, disks, public IPs and other services can continue accruing charges until removed. The repository and documentation do not imply that an existing live lab has been deleted.
