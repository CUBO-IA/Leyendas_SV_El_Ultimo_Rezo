# Motor en red: varias computadoras de la misma red (wifi/LAN o Tailscale) juegan
# contra este motor, cada una con su propia partida.
#   powershell -ExecutionPolicy Bypass -File tools\motor_en_red.ps1
#
# No toca el .env: API_HOST=0.0.0.0 vale solo mientras esta ventana está abierta.
# Al cerrarla (Ctrl+C), el motor vuelve a ser solo local la próxima vez.
# Ojo: cualquiera en esa red puede usar el motor (y tu clave de NVIDIA): úsalo en
# redes de confianza.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$port = 8000

Write-Host ""
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

Write-Host ""
Write-Host "Arrancando el motor en 0.0.0.0:$port (Ctrl+C para detenerlo)..." -ForegroundColor Yellow
Write-Host ""
$env:API_HOST = "0.0.0.0"
$env:API_PORT = "$port"
Set-Location $root
& (Join-Path $root ".venv\Scripts\python.exe") -m server
