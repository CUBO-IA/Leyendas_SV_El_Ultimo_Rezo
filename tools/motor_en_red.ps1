﻿# Motor en red: varias computadoras juegan contra este motor.
#   powershell -ExecutionPolicy Bypass -File tools\motor_en_red.ps1            # red local / Tailscale
#   powershell -ExecutionPolicy Bypass -File tools\motor_en_red.ps1 -Publico   # internet (Tailscale Funnel)
#
# No toca el .env: lo que cambia (API_HOST, ACCESS_CODE) vale solo mientras esta ventana
# está abierta. Al cerrarla (Ctrl+C) todo vuelve a ser local y Funnel se apaga.
#
# -Publico (experimental): publica el motor en https://<tu-equipo>.ts.net con Tailscale
# Funnel y exige un código de acceso (sin él solo responde /health), guardado en
# server\.access_code para que el zip que repartas siga sirviendo al reiniciar. Muestra
# el comando para crear ese zip (servidor.txt con la dirección y el código).
# Ojo: cualquiera con el zip puede jugar y gasta tu clave de NVIDIA.
param([switch]$Publico)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$port = 8000
$ts = "C:\Program Files\Tailscale\tailscale.exe"

Write-Host ""
if ($Publico) {
    Write-Host "== Leyendas SV: motor PÚBLICO (Tailscale Funnel) ==" -ForegroundColor Yellow
    if (-not (Test-Path $ts)) { throw "No encuentro Tailscale ($ts)." }
    $self = (& $ts status --json | ConvertFrom-Json).Self
    $publicUrl = "https://" + $self.DNSName.TrimEnd(".")
    $codeFile = Join-Path $root "server\.access_code"
    if (Test-Path $codeFile) {
        $code = (Get-Content $codeFile -Raw).Trim()
    } else {
        $chars = "abcdefghjkmnpqrstuvwxyz23456789".ToCharArray()
        $code = "sv-" + (-join (1..10 | ForEach-Object { $chars | Get-Random }))
        Set-Content -Path $codeFile -Value $code -Encoding ascii -NoNewline
    }
    Write-Host ""
    Write-Host "Dirección pública: $publicUrl" -ForegroundColor Cyan
    Write-Host "Código de acceso:  $code" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Zip para repartir (la dirección y el código van dentro, en servidor.txt):"
    Write-Host "  powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1 -Name LeyendasSV-online -ServerUrl $publicUrl -Code $code"
    Write-Host "Quien lo descargue: abrir LeyendasSV.exe > 'Unirse a una partida' (busca solo)."
    Write-Host "Tú: juega desde esa misma carpeta (Jugar con el motor.bat) para que tu juego lleve el código."
    Write-Host ""
    Write-Host "Encendiendo Funnel..." -ForegroundColor Yellow
    & $ts funnel --bg $port
    if ($LASTEXITCODE -ne 0) {
        Write-Host "No se pudo encender Funnel. Habilítalo en https://login.tailscale.com/admin/settings/features (HTTPS) y en las políticas de acceso (funnel), y vuelve a intentar." -ForegroundColor Red
        exit 1
    }
    $env:API_HOST = "127.0.0.1"  # Funnel llega por localhost: el wifi no ve el motor
    $env:ACCESS_CODE = $code
} else {
    Write-Host "== Leyendas SV: motor en red ==" -ForegroundColor Yellow

    $ips = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }
    if (-not $ips) { throw "No hay ninguna red conectada." }

    Write-Host ""
    Write-Host "En las otras computadoras (con el zip del juego):" -ForegroundColor Cyan
    Write-Host "  doble clic en 'Jugar en red.bat' y escribir una de estas IP:"
    foreach ($ip in $ips) {
        Write-Host ("    {0,-16} ({1})" -f $ip.IPAddress, $ip.InterfaceAlias)
    }
    Write-Host "  o: LeyendasSV.exe -- --backend=http --api=http://$($ips[0].IPAddress):$port"

    # El firewall de Windows bloquea conexiones entrantes en redes "Públicas".
    $public = Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq "Public" }
    if ($public) {
        Write-Host ""
        Write-Host "AVISO: estas redes están como 'Públicas' y el firewall bloqueará a los demás:" -ForegroundColor Red
        foreach ($p in $public) { Write-Host "    $($p.InterfaceAlias) ($($p.Name))" }
        Write-Host "  Si es una red de confianza: Configuración > Red e Internet > (la red) > Red privada."
    }
    $rule = Get-NetFirewallRule -DisplayName "Leyendas SV motor" -ErrorAction SilentlyContinue
    if (-not $rule) {
        Write-Host ""
        Write-Host "Si Windows pregunta, permite Python SOLO en redes privadas." -ForegroundColor Cyan
        Write-Host "  O crea la regla una vez (PowerShell como administrador):"
        Write-Host "  New-NetFirewallRule -DisplayName 'Leyendas SV motor' -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Private"
    }
    $env:API_HOST = "0.0.0.0"
}

Write-Host ""
Write-Host "Arrancando el motor en $($env:API_HOST):$port (Ctrl+C para detenerlo)..." -ForegroundColor Yellow
Write-Host ""
$env:API_PORT = "$port"
Set-Location $root
try {
    & (Join-Path $root ".venv\Scripts\python.exe") -m server
} finally {
    if ($Publico) {
        & $ts funnel reset | Out-Null  # al cerrar, el motor deja de estar en internet
        Write-Host "Funnel apagado: el motor ya no está en internet." -ForegroundColor Yellow
    }
}
