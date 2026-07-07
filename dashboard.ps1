# sing-box portable dashboard (Windows)
# Usage: powershell -ExecutionPolicy Bypass -File dashboard.ps1

$env:ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER = "true"

$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Clash = "http://127.0.0.1:9090"
$Exe = Join-Path $Dir "sing-box.exe"
$Config = Join-Path $Dir "config-windows.json"

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
    Write-Host "  [*] Zapusk sing-box..." -ForegroundColor Yellow

    if (-not (Test-Path $Exe)) {
        Write-Host "  [!] sing-box.exe ne nayden" -ForegroundColor Red
        return
    }
    if (-not (Test-Path $Config)) {
        Write-Host "  [!] config-windows.json ne nayden" -ForegroundColor Red
        return
    }

    Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "set ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true && `"$Exe`" run -c `"$Config`" -D `"$Dir`"" -WindowStyle Hidden
    Start-Sleep -Seconds 5

    if (Is-Running) {
        Write-Host "  [+] ZAPUSHEN" -ForegroundColor Green
    } else {
        Write-Host "  [!] OSHIBKA - sm. sing-box.log" -ForegroundColor Red
    }
}

function Stop-SingBox {
    Write-Host ""
    Write-Host "  [*] Ostanovka sing-box..." -ForegroundColor Yellow
    Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "  [+] OSTANOVLЕН" -ForegroundColor Green
}

function Get-TrafficStats {
    $result = @{
        Up = 0
        Down = 0
        Connections = 0
        ExitIP = "?"
    }

    if (-not (Is-Running)) { return $result }

    try {
        $json = curl.exe -s --connect-timeout 2 "$Clash/connections" 2>$null
        if ($json) {
            $data = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($data -and $data.connections) {
                $result.Connections = $data.connections.Count
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
        if ($lp -lt 0) { $lp = 0; $rp = 0 }
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
    while ($true) {
        Clear-Host

        $running = Is-Running
        $stats = Get-TrafficStats

        $statusText = if ($running) {
            $proc = Get-Process -Name "sing-box" -ErrorAction SilentlyContinue | Select-Object -First 1
            $procId = if ($proc) { $proc.Id } else { "?" }
            "RUNNING (PID $procId)"
        } else { "STOPPED" }
        $statusColor = if ($running) { "Green" } else { "Red" }

        $header = @(
            @{ Text = ""; Color = "Cyan" }
            @{ Text = "              SING-BOX"; Color = "White" }
            @{ Text = ""; Color = "Cyan" }
            @{ Text = "  Status:    $statusText"; Color = $statusColor }
            @{ Text = "  Exit IP:   $($stats.ExitIP)"; Color = "Cyan" }
            @{ Text = ""; Color = "Cyan" }
            @{ Text = "  SOCKS5:    127.0.0.1:1080"; Color = "DarkGray" }
            @{ Text = "  HTTP:      127.0.0.1:8080"; Color = "DarkGray" }
            @{ Text = "  Clash:     127.0.0.1:9090"; Color = "DarkGray" }
        )
        Show-Box $header "STATUS"

        $upStr = Format-Bytes $stats.Up
        $dnStr = Format-Bytes $stats.Down

        $trafficLines = @(
            @{ Text = "  Upload:    $upStr"; Color = "Green" }
            @{ Text = "  Download:  $dnStr"; Color = "Green" }
            @{ Text = "  Conn:      $($stats.Connections) active"; Color = "White" }
        )
        Show-Box $trafficLines "TRAFFIC"

        $menuLines = @(
            @{ Text = "  [1] START  - zapustit sing-box"; Color = "Yellow" }
            @{ Text = "  [2] STOP   - ostanovit sing-box"; Color = "Yellow" }
            @{ Text = "  [3] EXIT   - vyhod"; Color = "Yellow" }
        )
        Show-Box $menuLines "MENU"

        Write-Host ""
        Write-Host "  Nazhmite klavishu..." -NoNewline -ForegroundColor DarkGray

        $key = $null
        $waited = 0
        while ($null -eq $key -and $waited -lt 5) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                } else {
                    Start-Sleep -Seconds 1
                    $waited++
                }
            } catch {
                Start-Sleep -Seconds 1
                $waited++
            }
        }

        if ($null -ne $key) {
            switch ($key.KeyChar.ToString()) {
                "1" { Start-SingBox; Start-Sleep -Seconds 2 }
                "2" { Stop-SingBox; Start-Sleep -Seconds 2 }
                "3" {
                    Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    return
                }
            }
        }
    }
}

Show-Dashboard
