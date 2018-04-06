# This script stops Azure VMs if they are running more than 3 days.
# Before use the sript it require few steps:
# 1. Need to create automation account with default settings.
# 2. Updates all modules.
# 3. Install necessary module AzureRM.Insights.
# 4. Create Credential account with name 'AzureCred' and provide azure credentials with contribution permission: login@domain.com and password
# 5. Create new powershell runbook and copy code to it 
# 6. Save, test and publsih, then create scheduler for every day.
