##

<#
.SYNOPSIS
    Invites B2B Guests, adds them to a new Group, and assigns that group to an (1) Enterprise App.

.DESCRIPTION
    1. Connects to MS Graph with necessary scopes.
    2. Creates a new Security Group.
    3. Reads CSV (Name, Email).
    4. Invites users (if not exists) or retrieves them.
    5. Adds users to the new group.
    6. Prompts to assign the group to an Enterprise App.

.EXAMPLE CSV must have these headers to parse correctly
    CSV Format (headers required):
    Name,Email
    John Doe,john.doe@partner.com
    Jane Smith,jane.smith@vendor.com
#>

# 1. Connect and Prompt for Permissions
Write-Host "Connecting to Microsoft Entra..." -ForegroundColor Cyan
$Scopes = @("User.Invite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All", "AppRoleAssignment.ReadWrite.All", "Application.Read.All")
Connect-MgGraph -Scopes $Scopes

# 2. Group Creation
$GroupName = Read-Host "Enter the name for the NEW Security Group (e.g., 'App_Vendor_Access')"
$GroupDesc = "External guests for Enterprise App Access"

Write-Host "Creating group '$GroupName'..." -ForegroundColor Cyan
try {
    $NewGroup = New-MgGroup -DisplayName $GroupName -MailEnabled:$false -SecurityEnabled:$true -MailNickname ($GroupName -replace " ", "") -Description $GroupDesc
    Write-Host "Group Created! ID: $($NewGroup.Id)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create group. It may already exist."
    # Attempt to retrieve if it failed (optional logic)
    $NewGroup = Get-MgGroup -Filter "DisplayName eq '$GroupName'" | Select-Object -First 1
}

# 3. Import CSV
$CsvPath = Read-Host "Enter the full path to your .csv file (e.g., C:\temp\guests.csv)"
if (-not (Test-Path $CsvPath)) { Write-Error "File not found!"; exit }
$Users = Import-Csv $CsvPath

# 4. Process Users
foreach ($Row in $Users) {
    $UserEmail = $Row.Email
    $UserName  = $Row.Name
    $GuestUser = $null

    Write-Host "Processing $UserEmail..." -NoNewline

    # Check if user already exists
    $ExistingUser = Get-MgUser -Filter "Mail eq '$UserEmail' or UserPrincipalName eq '$UserEmail'" -ErrorAction SilentlyContinue

    if ($ExistingUser) {
        Write-Host " [Exists]" -ForegroundColor Yellow
        $GuestUser = $ExistingUser
    }
    else {
        # Invite New Guest
        Write-Host " [Inviting]" -ForegroundColor Cyan
        
        $InviteParams = @{
            InvitedUserEmailAddress = $UserEmail
            InviteRedirectUrl = "https://myapps.microsoft.com" # Default landing page
            InvitedUserDisplayName = $UserName
            SendInvitationMessage = $true
            InvitedUserMessageInfo = @{
                CustomizedMessageBody = "Welcome! You have been granted access to our Enterprise Application."
            }
        }
        
        try {
            $InviteResult = New-MgInvitation -BodyParameter $InviteParams
            $GuestUser = $InviteResult.InvitedUser
        }
        catch {
            Write-Error "Failed to invite $UserEmail : $_"
            continue
        }
    }

    # Add to Group, I Increased the wait time to 5 for full latency handling
    if ($GuestUser) {
        try {
            # Small delay for replication if newly created
            if (-not $ExistingUser) { Start-Sleep -Seconds 5 }
            
            New-MgGroupMember -GroupId $NewGroup.Id -DirectoryObjectId $GuestUser.Id -ErrorAction Stop
            Write-Host " - Added to Group." -ForegroundColor Green
        }
        catch {
            # Catch error if already in group
            Write-Host " - Already in group or error." -ForegroundColor Green
        }
    }
}

# 5. Assign Group to Enterprise Application
Write-Host "`n--- Access Assignment ---" -ForegroundColor Magenta
$AssignApp = Read-Host "Do you want to grant this group access to an Enterprise App now? (Y/N)"

if ($AssignApp -eq "Y") {
    $AppName = Read-Host "Enter the Display Name of the Enterprise App (e.g., 'Salesforce')"
    
    # Search for Service Principal (Enterprise App)
    $ServicePrincipal = Get-MgServicePrincipal -Filter "DisplayName eq '$AppName'" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($ServicePrincipal) {
        Write-Host "Found App: $($ServicePrincipal.DisplayName) ($($ServicePrincipal.Id))" -ForegroundColor Green
        Write-Host "Written By Curtis Jones" -ForegroundColor Cyan
		Start-Sleep 10
        # Get 'Default Access' or specific role. Default ID is usually all zeros for basic access.
        # For this script, we assume default access.
        $AppRoleID = [Guid]::Empty.ToString() 

        $AppRoleParams = @{
            PrincipalId = $NewGroup.Id
            ResourceId  = $ServicePrincipal.Id
            AppRoleId   = $AppRoleID 
        }

        try {
            New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $ServicePrincipal.Id -BodyParameter $AppRoleParams
            Write-Host "SUCCESS: Group '$GroupName' assigned to '$AppName'." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to assign access. The app might require specific roles defined."
            Write-Host "Error Details: $_"
        }
    }
    else {
        Write-Error "Application '$AppName' not found. Please check the name and try manually."
    }
}

Write-Host "`nScript Complete."