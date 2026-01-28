// 1. Define the Pentester's Account and the "Allow List" of Apps
let PentesterUPN = "pentester@<domain.io>"; // Update with the actual UPN
let AllowedApps = dynamic([
    "Microsoft Azure Virtual Network Gateway", // VPN App Name
    "Dev-App-Portal",                          // Your specific Dev App
    "Azure SSH Login"                          // If using AAD Login for Linux
]);
// 2. Combine Interactive and Non-Interactive Sign-ins
union SigninLogs, AADNonInteractiveUserSignInLogs
| where TimeGenerated > ago(24h)
| where UserPrincipalName =~ PentesterUPN
// 3. Filter for SUCCESSFUL sign-ins only (we care if they got in)
| where ResultType == 0 
// 4. The Core Logic: Alert if they access an App NOT in the Allow List
| where AppDisplayName !in (AllowedApps) 
| extend DetectionContext = strcat("Lateral Movement Attempt: User accessed unauthorized app '", AppDisplayName, "'")
| project 
    TimeGenerated, 
    DetectionContext, 
    UserPrincipalName, 
    AppDisplayName, 
    IPAddress, 
    ResourceDisplayName, 
    UserAgent
| sort by TimeGenerated desc

// You can break this KQL cmd up or add to for your env.