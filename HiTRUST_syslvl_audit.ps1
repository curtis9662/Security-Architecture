Write-Host "Curtis' CISSP ISO27001 | HITRUST Validator" -ForegroundColor Cyan

# Blactec CISSP 8 Domain System Configuration Tool
# ISO 27001 & HITRUST Compliant PowerShell GUI App

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Logging Setup
$LogFile = "$env:USERPROFILE\Blactec_CISSP_Tool.log"
Function Write-Log {
    param ([string]$Message)
    "$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) - $Message" | Out-File -Append -FilePath $LogFile
}

Write-Log "Script Started"

# Function to collect system information securely
Function Get-SystemInventory {
    Try {
        $inventory = @{}
        
        # Domain 1: Security and Risk Management
        $inventory["Security and Risk Management"] = @{
            "Windows Version" = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption
            "Last Boot Time" = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
            "Installed Antivirus" = (Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Select-Object displayName, productState | Format-Table -AutoSize | Out-String).Trim()
            "Windows Defender Status" = (Get-MpComputerStatus | Select-Object AMServiceEnabled, AntispywareEnabled, AntivirusEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, RealTimeProtectionEnabled | Format-Table -AutoSize | Out-String).Trim()
        }

        # Domain 2: Asset Security
        $inventory["Asset Security"] = @{
            "Computer Name" = $env:COMPUTERNAME
            "Domain/Workgroup" = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
            "BitLocker Status" = (Get-BitLockerVolume -ErrorAction SilentlyContinue | Format-Table -AutoSize | Out-String).Trim()
            "Execution Policy" = Get-ExecutionPolicy
            "Last Login Time" = (Get-EventLog -LogName Security -InstanceId 4624 | Sort-Object TimeGenerated -Descending | Select-Object -First 1).TimeGenerated
            "Last Login Result" = (Get-EventLog -LogName Security -InstanceId 4624 | Sort-Object TimeGenerated -Descending | Select-Object -First 1).EntryType
        }

        # Domain 3: Security Architecture and Engineering
        $inventory["Security Architecture and Engineering"] = @{
            "System Information" = (Get-CimInstance -ClassName Win32_ComputerSystem | Format-List | Out-String).Trim()
            "Group Policies Applied" = (gpresult /r | Out-String).Trim()
            "User Groups (WHOAMI)" = (whoami /groups | Out-String).Trim()
        }

        # Domain 4: Communication and Network Security
        $inventory["Communication and Network Security"] = @{
            "TLS Versions Enabled" = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\*' | Select-Object PSChildName | Format-Table -AutoSize | Out-String).Trim()
            "Internet Connection Protocols" = (Get-NetTCPConnection | Group-Object State | Format-Table Name, Count | Out-String).Trim()
            "NIC Configuration" = (Get-NetAdapter | Format-Table -AutoSize | Out-String).Trim()
        }

        # Domain 5: Identity and Access Management (IAM)
        $inventory["Identity and Access Management"] = @{
            "User Information" = (Get-LocalUser | Select-Object Name, Enabled, LastLogon | Format-Table -AutoSize | Out-String).Trim()
            "User Profiles" = (Get-CimInstance -ClassName Win32_UserProfile | Select-Object LocalPath, LastUseTime | Format-Table -AutoSize | Out-String).Trim()
            "Admin Privileges" = (Get-LocalGroupMember -Group "Administrators" | Format-Table -AutoSize | Out-String).Trim()
            "Identity Configurations and Policies" = (Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" | Format-List | Out-String).Trim()
        }
        
        return $inventory
    }
    Catch {
        Write-Log "Error in Get-SystemInventory: $_"
    }
}

# GUI Configuration
Function Show-InventoryGUI {
    $inventory = Get-SystemInventory

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Blactec CISSP 8 Domain System Inventory"
    $form.Size = New-Object System.Drawing.Size(900, 700)
    $form.StartPosition = "CenterScreen"

    $statusBar = New-Object System.Windows.Forms.StatusBar
    $statusBar.Text = "Ready"
    $form.Controls.Add($statusBar)

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

    foreach ($domain in $inventory.Keys) {
        $tabPage = New-Object System.Windows.Forms.TabPage
        $tabPage.Text = $domain

        $rtb = New-Object System.Windows.Forms.RichTextBox
        $rtb.Dock = [System.Windows.Forms.DockStyle]::Fill
        $rtb.ReadOnly = $true
        $rtb.Font = New-Object System.Drawing.Font("Consolas", 10)
        $rtb.BackColor = [System.Drawing.Color]::WhiteSmoke

        foreach ($item in $inventory[$domain].Keys) {
            $rtb.AppendText("=== $item ===`r`n")
            $rtb.AppendText("$($inventory[$domain][$item])`r`n`r`n")
        }

        $tabPage.Controls.Add($rtb)
        $tabControl.TabPages.Add($tabPage)
    }

    $form.Controls.Add($tabControl)
    
    $exportButton = New-Object System.Windows.Forms.Button
    $exportButton.Text = "Export to HTML Report"
    $exportButton.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $exportButton.Add_Click({
        $statusBar.Text = "Exporting..."
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "HTML Files (*.html)|*.html"
        $saveDialog.DefaultExt = "html"
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $htmlReport = Export-InventoryToHTML -Inventory $inventory
            $htmlReport | Out-File -FilePath $saveDialog.FileName
            [System.Windows.Forms.MessageBox]::Show("Report saved to $($saveDialog.FileName)", "Export Complete")
            $statusBar.Text = "Ready"
        }
    })
    $form.Controls.Add($exportButton)

    $form.ShowDialog()
}

# HTML Report Generation
Function Export-InventoryToHTML {
    param([hashtable]$Inventory)
    $html = "<html><head><title>System Inventory Report</title></head><body><h1>System Inventory</h1>"
    foreach ($domain in $Inventory.Keys) {
        $html += "<h2>$domain</h2>"
        foreach ($item in $Inventory[$domain].Keys) {
            $html += "<h3>$item</h3><pre>$($Inventory[$domain][$item])</pre>"
        }
    }
    $html += "</body></html>"
    return $html
}

Show-InventoryGUI
