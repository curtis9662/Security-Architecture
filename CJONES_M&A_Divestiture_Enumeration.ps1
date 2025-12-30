<#
.SYNOPSIS
M&A / Divestiture SBOM Identity, GPO, and NIST Evidence Collector

.AUTHOR
Cybersecurity Architecture – M&A / SBOM

.REQUIREMENTS
- PowerShell 5.1+
- Microsoft.Graph
- RSAT / GroupPolicy
- Domain-joined (for GPO extraction)

.GRAPH SCOPES
Application.Read.All
Directory.Read.All
Policy.Read.All
#>

# =========================
# INITIALIZATION
# =========================
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BasePath  = "$PWD\SBOM_MA_Evidence_$Timestamp"
New-Item -ItemType Directory -Path $BasePath -Force | Out-Null

# =========================
# MODULE VALIDATION
# =========================
$Modules = @("Microsoft.Graph","GroupPolicy")
foreach ($Module in $Modules) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Install-Module $Module -Scope CurrentUser -Force
    }
}

# =========================
# CONNECT TO MICROSOFT GRAPH
# =========================
Connect-MgGraph -Scopes `
    "Application.Read.All",
    "Directory.Read.All",
    "Policy.Read.All"

# =========================
# SECTION 1 – IDENTITY & APPLICATION INVENTORY
# =========================

## Enterprise Applications
$EnterpriseApps = Get-MgServicePrincipal -All |
Select DisplayName, AppId, ServicePrincipalType, AccountEnabled, PublisherName

$EnterpriseApps | Export-Csv "$BasePath\EnterpriseApplications.csv" -NoTypeInformation

## Microsoft First-Party Applications
$MicrosoftApps = $EnterpriseApps |
Where-Object { $_.PublisherName -like "*Microsoft*" }

$MicrosoftApps | Export-Csv "$BasePath\MicrosoftApplications.csv" -NoTypeInformation

## Managed Identities
$ManagedIdentities = $EnterpriseApps |
Where-Object { $_.ServicePrincipalType -eq "ManagedIdentity" }

$ManagedIdentities | Export-Csv "$BasePath\ManagedIdentities.csv" -NoTypeInformation

# =========================
# SECTION 2 – GPO SECURITY CONFIGURATION
# =========================

## Password & Lockout Policy
try {
    $PasswordPolicy = Get-ADDefaultDomainPasswordPolicy
    $PasswordPolicy |
    Select MinPasswordLength, LockoutThreshold, LockoutDuration, ComplexityEnabled |
    Export-Csv "$BasePath\GPO_PasswordPolicy.csv" -NoTypeInformation
}
catch {
    "Password Policy collection failed (non-domain system)" |
    Out-File "$BasePath\GPO_Errors.txt" -Append
}

## Local Administrators
try {
    Get-LocalGroupMember -Group "Administrators" |
    Select Name, ObjectClass |
    Export-Csv "$BasePath\LocalAdmins.csv" -NoTypeInformation
}
catch {
    "Local Admin collection failed" |
    Out-File "$BasePath\GPO_Errors.txt" -Append
}

## Network Access Security Policy
try {
    $SecPolPath = "$BasePath\secpol.cfg"
    secedit /export /cfg $SecPolPath | Out-Null
    Select-String "Network access" $SecPolPath |
    Out-File "$BasePath\NetworkAccessPolicies.txt"
}
catch {
    "Network Access policy extraction failed" |
    Out-File "$BasePath\GPO_Errors.txt" -Append
}

# =========================
# SECTION 3 – NIST CONTROL EVIDENCE MAPPING
# =========================

$NISTControls = @(
    @{ Control="IA-5"; Area="Endpoint"; Evidence="Password Length & Complexity" },
    @{ Control="AC-2"; Area="Server"; Evidence="Enterprise Applications Inventory" },
    @{ Control="AC-6"; Area="VM"; Evidence="Managed Identity Privilege Scope" },
    @{ Control="CM-8"; Area="All"; Evidence="SBOM Application Inventory" },
    @{ Control="SI-7"; Area="All"; Evidence="Third-Party Component Integrity" }
)

$NISTControls | Export-Csv "$BasePath\NIST_Control_Mapping.csv" -NoTypeInformation

# =========================
# SECTION 4 – EXECUTION SUMMARY
# =========================

$Summary = [PSCustomObject]@{
    ExecutionTime        = Get-Date
    EnterpriseApps       = $EnterpriseApps.Count
    MicrosoftApps        = $MicrosoftApps.Count
    ManagedIdentities    = $ManagedIdentities.Count
    OutputDirectory      = $BasePath
}

$Summary | Export-Csv "$BasePath\ExecutionSummary.csv" -NoTypeInformation

Write-Host "`nSBOM M&A Evidence Collection Complete"
Write-Host "Written by Curtis Jones" -ForegroundColor Magenta
Write-Host "Artifacts saved to: $BasePath`n"