Install-Module Microsoft.Graph -Scope CurrentUser


<#
.SYNOPSIS
    Enumerates Entra ID MFA Tenant Configuration and User Registration details.
    
.DESCRIPTION
    This script retrieves:
    1. The Tenant-wide Authentication Methods Policy (which methods are allowed/disabled).
    2. A report of all users and their specifically registered authentication methods.
    
.NOTES
    Requires the following Microsoft Graph Scopes:
    - Policy.Read.All
    - UserAuthenticationMethod.Read.All
    - User.Read.All
#>

# --- Configuration ---
$ExportPath = "C:\Temp\EntraMFA_Report_$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$TenantConfigPath = "C:\Temp\EntraTenantConfig_$(Get-Date -Format 'yyyyMMdd-HHmm').csv"

# --- 1. Connection ---
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
    Connect-MgGraph -Scopes "Policy.Read.All", "UserAuthenticationMethod.Read.All", "User.Read.All" -NoWelcome
    Write-Host "Successfully connected." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph. Please ensure you have the required permissions."
    exit
}

# --- 2. Tenant Configuration (Modern Policies) ---
Write-Host "`n[1/3] Retrieving Tenant Authentication Method Policies..." -ForegroundColor Cyan

$authMethodPolicies = @()
$methodTypes = @(
    "microsoftAuthenticator", 
    "fido2", 
    "windowsHelloForBusiness", 
    "sms", 
    "voice", 
    "email", 
    "softwareOath", 
    "temporaryAccessPass"
)

foreach ($method in $methodTypes) {
    try {
        # Retrieve the specific policy configuration for each method type
        $config = Get-MgPolicyAuthenticationMethodAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId $method -ErrorAction SilentlyContinue
        
        if ($config) {
            $policyObj = [PSCustomObject]@{
                Method          = $config.Id
                State           = $config.State
                ExcludeTargets  = ($config.ExcludeTargets.Id -join ", ")
                IncludeTargets  = ($config.IncludeTargets.Id -join ", ")
            }
            $authMethodPolicies += $policyObj
        }
    }
    catch {
        Write-Warning "Could not retrieve policy for $method"
    }
}

# Export Tenant Config
$authMethodPolicies | Export-Csv -Path $TenantConfigPath -NoTypeInformation
Write-Host "Tenant Policy Configuration exported to: $TenantConfigPath" -ForegroundColor Green

# --- 3. User MFA Registration Details ---
Write-Host "`n[2/3] Retrieving Users and Registered Methods (This may take time)..." -ForegroundColor Cyan

$users = Get-MgUser -All -Property Id, UserPrincipalName, DisplayName
$userReport = @()
$totalUsers = $users.Count
$i = 0

foreach ($user in $users) {
    $i++
    $percentComplete = [math]::Round(($i / $totalUsers) * 100)
    Write-Progress -Activity "Processing Users" -Status "Processing $($user.UserPrincipalName)" -PercentComplete $percentComplete

    try {
        # Get registered methods for the user
        $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction Stop
        
        #Flatten methods into a readable string
        $registeredMethodsList = $methods | ForEach-Object { $_.AdditionalProperties["@odata.type"].Replace("#microsoft.graph.", "") }
        
        # Check specific common methods for easier reporting
        $hasAuthenticator = $registeredMethodsList -contains "microsoftAuthenticatorAuthenticationMethod"
        $hasPhone         = ($registeredMethodsList -contains "phoneAuthenticationMethod") -or ($registeredMethodsList -contains "mobilePhoneAuthenticationMethod")
        $hasFido          = $registeredMethodsList -contains "fido2AuthenticationMethod"
        
        $userObj = [PSCustomObject]@{
            UserPrincipalName    = $user.UserPrincipalName
            DisplayName          = $user.DisplayName
            MfaRegistered        = if ($methods.Count -gt 0) { $true } else { $false }
            MethodCount          = $methods.Count
            Methods              = ($registeredMethodsList -join ", ")
            HasApp               = $hasAuthenticator
            HasPhone             = $hasPhone
            HasKey               = $hasFido
        }
        $userReport += $userObj
    }
    catch {
        # Handle users where permissions might be denied or user not found
        $userObj = [PSCustomObject]@{
            UserPrincipalName    = $user.UserPrincipalName
            DisplayName          = $user.DisplayName
            MfaRegistered        = "Error/Unknown"
            MethodCount          = 0
            Methods              = "Error retrieving methods"
            HasApp               = $false
            HasPhone             = $false
            HasKey               = $false
        }
        $userReport += $userObj
    }
}

# --- 4. Export User Report ---
Write-Host "`n[3/3] Exporting User Report..." -ForegroundColor Cyan
$userReport | Export-Csv -Path $ExportPath -NoTypeInformation
Write-Host "User MFA Report exported to: $ExportPath" -ForegroundColor Green

Write-Host "`nScript Completed." -ForegroundColor Green