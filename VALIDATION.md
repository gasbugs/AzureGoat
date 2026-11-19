# Verification status — 2026-11-19

## Completed

- Terraform initialization with AzureRM 4.81.0, Archive 2.8.1 and Random 3.9.1.
- `terraform fmt -check` and `terraform validate`.
- Python build regression test: repeated rendering preserves source files, excludes old runtime packages and updates the generated API, asset and VM addresses.
- Full Terraform plan against the currently selected subscription: **451 additions, 0 changes, 0 deletions**. Most additions are the existing 140 asset files uploaded into three lab containers.

## Not yet verified

**No live AzureGoat deployment has been performed for this update.** Application availability, remote Function builds, VM initialization and Automation runbook execution remain unverified until an eligible target subscription is approved and the live tests succeed.

At the time of checking, the current Free Trial subscription had East US Y1 quota **0**, and all **4/4 regional vCPUs** were in use by the separate firewall lab. A valid Terraform plan does not bypass those limits. Existing lab resources were not changed or deleted.

Another signed-in paid subscription showed Y1 SKU quota 30 and 10 available regional vCPUs, but its reported aggregate App Service regional limit was 0. These read-only figures do not guarantee that a deployment will be accepted. Its use for this lab is awaiting the user's choice.

The plan file is ignored and is specific to its selected subscription. Generate a fresh plan after choosing or changing the target subscription; do not apply an old saved plan to a different account.
