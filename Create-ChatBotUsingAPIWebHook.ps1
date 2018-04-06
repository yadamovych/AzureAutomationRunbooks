<#
 .SYNOPSIS
    Deploys a template to Azure

 .DESCRIPTION
    Deploys an Azure Resource Manager template for Bot Channels Registration which you can call via webhook with input parameters. 

 .PARAMETER resourceGroupName
    The resource group where the template will be deployed. Can be the name of an existing or a new resource group.

 .PARAMETER resourceGroupLocation
    Optional, a resource group location. If specified, will try to create a new resource group in this location. If not specified, assumes resource group is existing.

 .PARAMETER deploymentName
    The deployment name.

 .PARAMETER templateFilePath
    Optional, path to the template file. Defaults to template.json.
    https://azfs18.blob.core.windows.net/arm/template.json

 .PARAMETER parametersFilePath
    Optional, path to the parameters file. Defaults to parameters.json. If file is not found, will prompt for parameter values based on template.
    https://azfs18.blob.core.windows.net/arm/parameters.json
#>

Param (
 [Parameter(Mandatory=$true)]
 [object]$WebhookData
 )

#Login
$Conn = Get-AutomationConnection -Name AzureRunAsConnection 
Add-AzureRMAccount -Credential (Get-AutomationPSCredential -Name 'AzureCred')
Set-AzureRmContext $Conn.SubscriptionId

$ApplicationDisplayName = $WebhookData.RequestHeader.AppName
$resourceGroupName = Get-AutomationVariable -Name 'External_BOT_ResourceGroupName'
$resourceGroupLocation = Get-AutomationVariable -Name 'External_BOT_ResourceGroupLocation'
$deploymentName = Get-AutomationVariable -Name 'External_BOT_DeploymentName'
$templateFilePath = Get-AutomationVariable -Name 'External_BOT_Template'
$parametersFilePath = Get-AutomationVariable -Name 'External_BOT_Parameters'
$localtemplate = 'C:\Temp\template.json'
$localparameters = 'C:\Temp\parameters.json'

#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************

#Create Azure Active Directory appid and password
Function CreateADSP ($ApplicationDisplayName)
{
        Import-Module AzureRM.Resources

        $ServicePrincipal = Get-AzureRmADServicePrincipal -SearchString $ApplicationDisplayName

        if (!$ServicePrincipal)
        {
        
        $Password = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..8] -join ''

        $ServicePrincipal = New-AzureRMADServicePrincipal -DisplayName $ApplicationDisplayName -Verbose
        New-AzureRmADSpCredential -ObjectId $ServicePrincipal.Id -Password ($Password | ConvertTo-SecureString -AsPlainText -Force) -Verbose
        Get-AzureRmADServicePrincipal -ObjectId $ServicePrincipal.Id 

        $NewRole = $null
        $Retries = 0;
        While ($NewRole -eq $null -and $Retries -le 6)
            {
                # Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
                Sleep 15
                New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $ServicePrincipal.ApplicationId | Write-Verbose -ErrorAction SilentlyContinue
                $NewRole = Get-AzureRMRoleAssignment -ObjectId $ServicePrincipal.Id -ErrorAction SilentlyContinue
                $Retries++;
            }
        }
        
    $Return = @{}
    $Return.Add('appid', $ServicePrincipal[-1].ApplicationId.Guid)
    $Return.Add('password', $Password) 

    return $Return
}

$AzureADSP =  CreateADSP $ApplicationDisplayName

#Create or check for existing resource group
$resourceGroupName = Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if(!$resourceGroupName)
{
    Write-Output "Resource group '$resourceGroupName' does not exist. Creating resource group '$resourceGroupName' in location '$resourceGroupLocation'";
    New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation
}
else{
    Write-Output "Using existing resource group '$resourceGroupName'";
}

# Start the deployment
Write-Output "Starting deployment...";

$parameters = @{}
$parameters.Add('botId', $ApplicationDisplayName)

if ($AzureADSP.password)
{
    $parameters.Add('appId', $AzureADSP.appid)
    $parameters.Add('appSecret', $AzureADSP.password)
}

Invoke-WebRequest -Uri $templateFilePath -OutFile $localtemplate
Invoke-WebRequest -Uri $parametersFilePath -OutFile $localparameters

$deploymentParameters = @{
        Mode = "Incremental"
        Name = $deploymentName
        ResourceGroupName = (Get-AutomationVariable -Name 'External_BOT_ResourceGroupName')
        TemplateFile = $localtemplate
        TemplateParameterFile = $localparameters
    }    

     foreach ($parameter in $parameters.GetEnumerator() | Where-Object {$_ -ne $null})
    {
		Write-Host "add '$($parameter.Key)' with value '$($parameter.Value)'"
        $deploymentParameters.Add($parameter.Key, $parameter.Value)
    }    

    New-AzureRmResourceGroupDeployment @deploymentParameters -Verbose

# Sending Mail.
$Subject = "Bot Channels Registration has been created:  $ApplicationDisplayName"
$BodyAppId = $AzureADSP.appid
$BodyPassword = $AzureADSP.password
$Body = "Bot Name:$ApplicationDisplayName <br /><br /> Application ID:$BodyAppId <br /><br /> Password:$BodyPassword" 
$To = "yadamovych@outlook.com"
$From = Get-AutomationVariable -Name 'External_BOT_Mail'
$Cred = Get-AutomationPSCredential -Name 'AzureCred'

Write-Output "Sending mail ..."
Send-MailMessage -To $To `
                 -Subject $Subject  `
                 -Body $Body `
                 -UseSsl `
                 -Port 587  `
                 -SmtpServer 'smtp.office365.com' `
                 -From $From `
                 -BodyAsHtml `
                 -Credential $Cred `
                 -Verbose

                