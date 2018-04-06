#Login
$Conn = Get-AutomationConnection -Name AzureRunAsConnection 
Add-AzureRMAccount -Credential (Get-AutomationPSCredential -Name 'AzureCred')
Set-AzureRmContext $Conn.SubscriptionId

$ResourceGroups = Get-AzureRmResourceGroup
#$ResourceGroups = Get-AzureRmResourceGroup "Demo" # Run only for one resource group.

ForEach ($ResourceGroup in $ResourceGroups) {


    $ActivityLog = Get-AzureRmLog -ResourceGroup $ResourceGroup.ResourceGroupName -StartTime ([DateTime]::Now - [TimeSpan]::FromHours(120)) -EndTime ([DateTime]::Now) -WarningAction silentlyContinue | 
    Where-Object {$_.Authorization.Action -eq 'Microsoft.Compute/virtualMachines/start/action' -or $_.Authorization.Action -eq 'Microsoft.Compute/virtualMachines/deallocate/action'} |
    Sort-Object EventTimestamp -Descending |  
    Select-Object caller, @{Name = "Action"; Expression = {$_.Authorization.Action.Split("/")[-2]}}, @{Name = "VM"; Expression = {$_.Authorization.Scope.Split("/")[-1]}}, EventTimestamp
    
    $VirtualMachines = Get-AzureRmVM -ResourceGroupName $ResourceGroup.ResourceGroupName

    foreach ($VirtualMachine in $VirtualMachines) {

        $VMState = $ActivityLog | Where-Object {$_.VM -eq $VirtualMachine.Name}

        if ($VMState) {

            if ($VMState[0].Action -eq "start" -and $VMState[0].EventTimestamp -lt (Get-Date).AddDays(-3)) {

                Write-Output "VM " $VirtualMachine.Name "is running more then 3 days, since" $VMState[0].EventTimestamp "Process of deallocation starting ..."

                Stop-AzureRmVM -Name $VirtualMachine.Name -ResourceGroupName $ResourceGroup.ResourceGroupName -Force

            }
        }
    }
}