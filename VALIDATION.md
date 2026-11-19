# Verification status — 2026-11-19

## Actual deployment

AzureGoat was deployed to **Australia East** in the explicitly approved paid subscription, in isolated resource group `azuregoat-australiaeast`. The separate East US firewall lab was not modified. The empty failed East US AzureGoat group was removed and its absence verified.

- Y1 Linux Consumption plan: successfully created. Actual East US Y1 and B1 creation attempts failed with effective quota 0, despite a SKU API showing 30. This is specific to the tested subscription.
- VM: `Standard_D2s_v6`, Ubuntu 24.04 LTS. D2s_v7 was absent from the tested Australia East SKU list.
- Functions: Python 3.11 backend and Node.js 22 frontend on Functions 4.
- Cosmos DB: serverless database and both containers created; seven initial blog posts returned by the live API.
- SSH as the lab's Justin user: succeeded; Ubuntu 24.04, active Apache, Azure CLI 2.93.0 and the authorized key were verified inside the VM.
- Automation: `Get-AzureVM` completed and returned the deployed developer VM using the managed identity.
- Registration and login: succeeded with a uniquely named temporary lab user; a valid token and matching user were returned. Passwords and tokens were not logged.

## Regression checks

- Terraform initialization, formatting and validation succeeded. After the final deployment, a refreshed `terraform plan -detailed-exitcode` exited 0 with **No changes**. AzureRM 4 emits storage-account-name deprecation warnings; the locked provider version still supports those arguments.
- Build regression tests passed: repeated rendering does not mutate sources, excludes old runtime packages, renders deployment addresses and omits a nonexistent upstream font stylesheet.
- HTTP trigger routes no longer begin with `/`, which caused a double-slash route and an empty response instead of the UI.
- ZIP output paths include the source hash. Merely changing an app setting while retaining the same ZIP path did not reliably redeploy the changed code; the filename change makes the provider upload the new package.

The final live smoke test passed: frontend HTML, both application JS/CSS assets, seven seeded posts, a seeded image, registration and login.

## Scope and limits

These checks validate deployment, key application flows, VM initialization and runbook execution; they do not certify every exploitation exercise. Intentional application vulnerabilities, sample keys and public lab storage remain part of AzureGoat.

The live lab is retained and incurs charges. State, generated credentials, local variable files and plan files are ignored by Git. The smoke test creates clearly named `deployment-check-...@example.invalid` users in the isolated lab.

Australia East success in this paid subscription does not guarantee quota or capacity in another subscription, including Free Trial. No quota increase request was submitted.
