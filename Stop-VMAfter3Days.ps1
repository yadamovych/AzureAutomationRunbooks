# This script stops Azure VMs if they are running more than 3 days.
# Before use the sript it require few steps:
# 1. Need to create automation account with default settings
# 2. Updates all modules.
# 3. Install necessary module AzureRM.Insights.
# 4. Create Credential account with name 'AzureCred' and provide azure credentials with contribution permission: login@domain.com and password
# 5. Create new powershell runbook and copy code to it 
# 6. Save, test and publsih, then create scheduler for every day.

#Login
$Conn = Get-AutomationConnection -Name AzureRunAsConnection 
Add-AzureRMAccount -Credential (Get-AutomationPSCredential -Name 'AzureCred')
Set-AzureRmContext $Conn.SubscriptionId

# Run only for one resource group.
#$ResourceGroups = Get-AzureRmResourceGroup "Demo" 
# Run for all resource group in current subscription
$ResourceGroups = Get-AzureRmResourceGroup
$ALStartTime = "120"

ForEach ($ResourceGroup in $ResourceGroups) {

    # Get activity logs for last 5 days and filter stop, start VM acctions then sort by time.
    $ActivityLog = Get-AzureRmLog -ResourceGroup $ResourceGroup.ResourceGroupName -StartTime ([DateTime]::Now - [TimeSpan]::FromHours($ALStartTime)) -EndTime ([DateTime]::Now) -WarningAction silentlyContinue | 
    Where-Object {$_.Authorization.Action -eq 'Microsoft.Compute/virtualMachines/start/action' -or $_.Authorization.Action -eq 'Microsoft.Compute/virtualMachines/deallocate/action'} |
    Sort-Object EventTimestamp -Descending |  
    Select-Object caller, @{Name = "Action"; Expression = {$_.Authorization.Action.Split("/")[-2]}}, @{Name = "VM"; Expression = {$_.Authorization.Scope.Split("/")[-1]}}, EventTimestamp
    
    # Get all VMs for current $ResourceGroup
    $VirtualMachines = Get-AzureRmVM -ResourceGroupName $ResourceGroup.ResourceGroupName

    foreach ($VirtualMachine in $VirtualMachines) {

        # Get last activity for vm in a loop
        $VMState = $ActivityLog | Where-Object {$_.VM -eq $VirtualMachine.Name}

        if ($VMState) {

            # If last action start and less then 3 days then start deallocation
            if ($VMState[0].Action -eq "start" -and $VMState[0].EventTimestamp -lt (Get-Date).AddDays(-3)) {

                Write-Output "VM " $VirtualMachine.Name "is running more then 3 days, since" $VMState[0].EventTimestamp "Process of deallocation starting ..."

                Stop-AzureRmVM -Name $VirtualMachine.Name -ResourceGroupName $ResourceGroup.ResourceGroupName -Force

            }
        }
    }
}