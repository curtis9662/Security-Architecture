# --- CONFIGURATION ---
# Add the URLs here make sure they're fqdn's
$urlList = @(
    "https://www.google.com",
    "https://www.github.com",
    "http://expired.badssl.com",  # Example of bad cert
    "https://self-signed.badssl.com", # Example of self-signed
    "https://www.nonexistent-url-test.com"
)

# --- SCRIPT LOGIC ---
$results = foreach ($rawUrl in $urlList) {
    
    # Initialize default status values
    $output = [ordered]@{
        URL           = $rawUrl
        HostName      = "N/A"
        ResolvedIP    = "Failed"
        PortOpen      = $false
        HTTPStatus    = "Failed"
        CertStatus    = "N/A"
        ResponseTime  = "N/A"
    }

    try {
        # 1. Parse the URL to get the Hostname and Scheme
        $uri = [System.Uri]$rawUrl
        $output.HostName = $uri.Host
        $port = if ($uri.Scheme -eq "https") { 443 } else { 80 }

        # 2. DNS Resolution
        try {
            $dns = Resolve-DnsName -Name $uri.Host -Type A -ErrorAction Stop | Select-Object -First 1
            $output.ResolvedIP = $dns.IPAddress
        } catch {
            $output.ResolvedIP = "DNS Resolution Failed"
            # If DNS fails, we usually can't proceed, so we output current state
            [PSCustomObject]$output
            continue 
        }

        # 3. Test Network Connection (TCP)
        # We verify if the port (80 or 443) is actually reachable
        $tcpCheck = Test-NetConnection -ComputerName $uri.Host -Port $port -InformationLevel Quiet
        $output.PortOpen = $tcpCheck

        if ($tcpCheck) {
            # 4. Check HTTP Response & Certificate
            # We use a timer to measure latency
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                # This request will fail if the Cert is invalid unless we ignore checks (we want to know if it's valid, so we keep checks on)
                $req = Invoke-WebRequest -Uri $rawUrl -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                
                $sw.Stop()
                $output.HTTPStatus = $req.StatusCode
                $output.ResponseTime = "$($sw.Elapsed.TotalMilliseconds.ToString('N0')) ms"
                
                if ($uri.Scheme -eq "https") {
                    $output.CertStatus = "Valid"
                } else {
                    $output.CertStatus = "N/A (Non-HTTPS)"
                }

            } catch {
                $sw.Stop()
                # Handle specific Web/SSL errors
                if ($_.Exception.Response) {
                    $output.HTTPStatus = $_.Exception.Response.StatusCode
                } else {
                    $output.HTTPStatus = "Connection Error"
                }

                # specific check for SSL/TLS trust errors
                if ($_.Exception.Message -like "*trust relationship*" -or $_.Exception.Message -like "*certificate*") {
                    $output.CertStatus = "INVALID / Untrusted"
                } else {
                    $output.CertStatus = "Connection Failed"
                }
            }
        }

    } catch {
        $output.HostName = "Invalid URL Format"
    }

    # Return the object to the list
    [PSCustomObject]$output
}

# --- OUTPUT ---
# Display as a table
$results | Format-Table -AutoSize
