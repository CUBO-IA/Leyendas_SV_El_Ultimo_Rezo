# Build de Windows: exporta el juego y arma una carpeta autocontenida + zip.
#   powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1
# Requiere las plantillas de exportación de Godot 4.7.2 en
# %APPDATA%\Godot\export_templates\4.7.2.stable\ (Editor > Gestionar plantillas).
#
# Resultado (ignorado por git): game\export\LeyendasSV\ y game\export\LeyendasSV-windows.zip
#   LeyendasSV.exe (pck incrustado) + content\, contract\fixtures\, assets_generated\portraits\
#   (Paths.repo_root los busca junto al exe) + dos lanzadores .bat.
# Nada de server\ ni .env: la solución del caso nunca viaja con el cliente.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "game\export\LeyendasSV"
$godot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*" -Recurse `
    -Filter "Godot_v4.7.2-stable_win64_console.exe" | Select-Object -First 1
if (-not $godot) { throw "No encuentro Godot 4.7.2 (consola)." }

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null

Write-Host "1/4 Importando recursos..."
& $godot.FullName --headless --path (Join-Path $root "game") --import | Out-Null

Write-Host "2/4 Exportando..."
& $godot.FullName --headless --path (Join-Path $root "game") --export-release "Windows Desktop" (Join-Path $out "LeyendasSV.exe")
if (-not (Test-Path (Join-Path $out "LeyendasSV.exe"))) { throw "La exportación no produjo LeyendasSV.exe" }

Write-Host "3/4 Copiando datos públicos..."
foreach ($rel in @("content\public", "content\generated", "contract\fixtures", "assets_generated\portraits")) {
    $dst = Join-Path $out $rel
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item (Join-Path $root "$rel\*") $dst -Recurse -Force
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $out "Jugar con el motor.bat"),
    "@echo off`r`nrem Requiere el motor corriendo: .venv\Scripts\python -m server`r`nstart `"`" `"%~dp0LeyendasSV.exe`" -- --backend=http --api=http://127.0.0.1:8000`r`n", $utf8)
[IO.File]::WriteAllText((Join-Path $out "Jugar sin motor (demo).bat"),
    "@echo off`r`nrem Modo mock: respuestas de ejemplo, sin IA ni internet.`r`nstart `"`" `"%~dp0LeyendasSV.exe`" -- --backend=mock`r`n", $utf8)
[IO.File]::WriteAllText((Join-Path $out "Jugar en red.bat"),
    "@echo off`r`nrem Juega contra el motor de otra computadora de la misma red (tools\motor_en_red.ps1).`r`nset /p IP=IP de la computadora con el motor (ej. 192.168.1.50): `r`nif `"%IP%`"==`"`" exit /b`r`nstart `"`" `"%~dp0LeyendasSV.exe`" -- --backend=http --api=http://%IP%:8000`r`n", $utf8)
[IO.File]::WriteAllText((Join-Path $out "LEEME.txt"), @"
Leyendas SV: El Último Rezo de las Ánimas (Windows)

- "Jugar con el motor.bat": la versión completa, con testigos de IA y voz.
  Antes, desde la raíz del repo: .venv\Scripts\python -m server
- "Jugar en red.bat": varias computadoras de la misma red juegan contra un solo
  motor, cada una con su propia partida. En la computadora con el motor:
  powershell -ExecutionPolicy Bypass -File tools\motor_en_red.ps1
  (muestra la IP que hay que escribir aquí).
- "Jugar sin motor (demo).bat": respuestas de ejemplo, sin internet.
- LeyendasSV.exe a secas usa el modo guardado en Opciones.

Controles: clic o WASD/flechas para caminar; clic o E para hablar y examinar;
Tab o el botón Diario; Esc o el botón Pausa.
En el interrogatorio: escribe, elige una pregunta sugerida o pulsa "Hablar"
(o F1) y haz tu pregunta en voz alta; al hacer una pausa se envía sola.
Créditos de retratos y personajes: assets_generated\portraits\CREDITOS.md
"@, $utf8)

Write-Host "4/4 Comprimiendo..."
$zip = Join-Path $root "game\export\LeyendasSV-windows.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $out -DestinationPath $zip
"{0:N1} MB  {1}" -f ((Get-Item $zip).Length / 1MB), $zip
