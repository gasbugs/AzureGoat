$ErrorActionPreference = 'Stop'
Disable-AzContextAutosave -Scope Process
$AzureContext = (Connect-AzAccount -Identity -AccountId REPLACE_CLIENT_ID).Context
$AzureContext = Set-AzContext -SubscriptionId $AzureContext.Subscription.Id -DefaultProfile $AzureContext
Get-AzVM -ResourceGroupName REPLACE_RESOURCE_GROUP_NAME -DefaultProfile $AzureContext
