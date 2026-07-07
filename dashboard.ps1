# sing-box portable dashboard (Windows)
# Usage: powershell -ExecutionPolicy Bypass -File dashboard.ps1

# Required for sing-box 1.12.x compatibility
$env:ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER = "true"

$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Clash = "http://127.0.0.1:9090"
$Exe = Join-Path $Dir "sing-box.exe"
$Config = Join-Path $Dir "config-windows.json"
$Log = Join-Path $Dir "sing-box.log"

function Format-Bytes($b) {
    if ($b -ge 1GB) { return "{0:N2} GB" -f ($b / 1GB) }
    if ($b -ge 1MB) { return "{0:N1} MB" -f ($b / 1MB) }
    if ($b -ge 1KB) { return "{0:N0} KB" -f ($b / 1KB) }
    return "$b B"
}

function Is-Running {
    return [bool](Get-Process -Name "sing-box" -ErrorAction SilentlyContinue)
}

function Start-SingBox {
    Write-Host ""
    Write-Host "  [*] Starting sing-box..." -ForegroundColor Yellow

    if (-not (Test-Path $Exe)) {
        Write-Host "  [!] sing-box.exe not found" -ForegroundColor Red
        return
    }
    if (-not (Test-Path $Config)) {
        Write-Host "  [!] config-windows.json not found" -ForegroundColor Red
        return
    }

    Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Start-Process -FilePath $Exe -ArgumentList "run -c `"$Config`" -D `"$Dir`"" -WindowStyle Hidden
    Start-Sleep -Seconds 5

    if (Is-Running) {
        Write-Host "  [+] sing-box RUNNING" -ForegroundColor Green
    } else {
        Write-Host "  [!] FAILED - check sing-box.log" -ForegroundColor Red
    }
}

function Stop-SingBox {
    Write-Host ""
    Write-Host "  [*] Stopping sing-box..." -ForegroundColor Yellow
    Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "  [+] Stopped" -ForegroundColor Green
}

function Get-TrafficStats {
    $result = @{
        Up = 0
        Down = 0
        Connections = 0
        Proxies = @{}
        ExitIP = "?"
    }

    if (-not (Is-Running)) { return $result }

    try {
        $json = curl.exe -s --connect-timeout 2 "$Clash/connections" 2>$null
        if ($json) {
            $data = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($data -and $data.connections) {
                $result.Connections = $data.connections.Count
                foreach ($c in $data.connections) {
                    $result.Up += $c.upload
                    $result.Down += $c.download
                }
            }
            $result.Up = if ($data) { $data.uploadTotal } else { 0 }
            $result.Down = if ($data) { $data.downloadTotal } else { 0 }
        }
    } catch {}

    try {
        $ip = curl.exe -4 -sk --connect-timeout 3 --socks5 127.0.0.1:1080 https://ifconfig.me 2>$null
        if ($ip) { $result.ExitIP = $ip }
    } catch {}

    return $result
}

function Show-Box($lines, $title) {
    $w = 55
    $border = "+" + ("-" * $w) + "+"
    Write-Host $border -ForegroundColor Cyan
    if ($title) {
        $pad = $w - $title.Length - 4
        $lp = [int]($pad / 2)
        $rp = $pad - $lp
        Write-Host ("|" + " " * $lp + $title + " " * $rp + "|") -ForegroundColor Cyan
        Write-Host $border -ForegroundColor Cyan
    }
    foreach ($line in $lines) {
        $text = $line.Text
        $color = if ($line.Color) { $line.Color } else { "White" }
        $pad = $w - $text.Length
        if ($pad -lt 0) { $pad = 0 }
        Write-Host ("|" + $text + " " * $pad + "|") -ForegroundColor $color
    }
    Write-Host $border -ForegroundColor Cyan
}

function Show-Dashboard {
    $prevUp = 0
    $prevDown = 0
    $startTime = Get-Date

    while ($true) {
        Clear-Host

        $running = Is-Running
        $stats = Get-TrafficStats

        # Header
        $statusText = if ($running) {
            $proc = Get-Process -Name "sing-box" -ErrorAction SilentlyContinue | Select-Object -First 1
            $pid = if ($proc) { $proc.Id } else { "?" }
            "RUNNING  PID $pid"
        } else { "STOPPED" }
        $statusColor = if ($running) { "Green" } else { "Red" }

        $elapsed = (Get-Date) - $startTime
        $uptime = "{0:hh\:mm\:ss}" -f $elapsed

        $header = @(
            @{ Text = ""; Color = "Cyan" }
            @{ Text = "     SING-BOX PORTABLE"; Color = "White" }
            @{ Text = ""; Color = "Cyan" }
            @{ Text = "  Status:  $statusText"; Color = $statusColor }
            @{ Text = "  Uptime:  $uptime"; Color = "White" }
            @{ Text = "  Exit IP: $($stats.ExitIP)"; Color = "Cyan" }
            @{ Text = ""; Color = "Cyan" }
            @{ Text = "  SOCKS5:  127.0.0.1:1080"; Color = "DarkGray" }
            @{ Text = "  HTTP:    127.0.0.1:8080"; Color = "DarkGray" }
            @{ Text = "  Clash:   127.0.0.1:9090"; Color = "DarkGray" }
        )
        Show-Box $header "STATUS"

        # Traffic
        $upStr = Format-Bytes $stats.Up
        $dnStr = Format-Bytes $stats.Down

        $trafficLines = @(
            @{ Text = "  UP:    $upStr"; Color = "Green" }
            @{ Text = "  DOWN:  $dnStr"; Color = "Green" }
            @{ Text = "  CONN:  $($stats.Connections) active"; Color = "White" }
        )
        Show-Box $trafficLines "TRAFFIC"

        # Menu
        $menuLines = @(
            @{ Text = "  [1] START    - launch sing-box"; Color = "Yellow" }
            @{ Text = "  [2] STOP     - kill sing-box"; Color = "Yellow" }
            @{ Text = "  [3] STATUS   - check exit IP"; Color = "Yellow" }
            @{ Text = "  [Q] EXIT     - quit dashboard"; Color = "Yellow" }
        )
        Show-Box $menuLines "MENU"

        # Wait for input
        Write-Host ""
        Write-Host "  Press a key..." -NoNewline -ForegroundColor DarkGray

        $key = $null
        $waited = 0
        while ($null -eq $key -and $waited -lt 5) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
            } else {
                Start-Sleep -Seconds 1
                $waited++
            }
        }

        if ($null -ne $key) {
            switch ($key.KeyChar.ToString().ToLower()) {
                "1" { Start-SingBox; Start-Sleep -Seconds 2 }
                "2" { Stop-SingBox; Start-Sleep -Seconds 2 }
                "3" {
                    if (Is-Running) {
                        Write-Host ""
                        Write-Host "  Checking exit IP..." -ForegroundColor Yellow
                        try {
                            $ip = curl.exe -4 -sk --connect-timeout 5 --socks5 127.0.0.1:1080 https://ifconfig.me 2>$null
                            Write-Host "  Exit IP: $ip" -ForegroundColor Cyan
                        } catch {
                            Write-Host "  Exit IP: timeout" -ForegroundColor DarkGray
                        }
                        Start-Sleep -Seconds 3
                    } else {
                        Write-Host ""
                        Write-Host "  sing-box not running" -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
                "q" {
                    Write-Host ""
                    Write-Host "  Stopping sing-box..." -ForegroundColor Yellow
                    Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    Write-Host "  Bye!" -ForegroundColor Green
                    return
                }
            }
        }
    }
}

# --- Main ---
Show-Dashboard
