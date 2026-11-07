#!/usr/bin/env bash
# Build de Linux: exporta el juego y arma una carpeta autocontenida + tar.gz (+ AppImage opcional).
#   bash tools/build_linux.sh [--appimage]
# Requiere Godot 4.7.2 y las plantillas de exportación en
#   ~/.local/share/godot/export_templates/4.7.2.stable/ (Editor > Gestionar plantillas).
# Resultado (ignorado por git): game/export/LeyendasSV/ y game/export/LeyendasSV-linux.tar.gz
#   LeyendasSV.x86_64 (pck incrustado) + content/, contract/fixtures/, assets_generated/portraits/
#   (Paths.repo_root los busca junto al ejecutable) + dos lanzadores .sh.
# Nada de server/ ni .env: la solución del caso nunca viaja con el cliente.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/game/export/LeyendasSV"
TARGZ="$ROOT/game/export/LeyendasSV-linux.tar.gz"
APPIMAGE="$ROOT/game/export/LeyendasSV-x86_64.AppImage"
BIN="LeyendasSV.x86_64"

# --- Localizar Godot ---
find_godot() {
  local candidates=(
    "${GODOT_BIN:-}"
    "$HOME/.local/bin/Godot_v4.7.2-stable_linux.x86_64"
    "$HOME/Downloads/Godot_v4.7.2-stable_linux.x86_64"
    "/usr/local/bin/Godot_v4.7.2-stable_linux.x86_64"
    "/usr/bin/Godot_v4.7.2-stable_linux.x86_64"
  )
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  if command -v Godot_v4.7.2-stable_linux.x86_64 >/dev/null 2>&1; then
    echo "Godot_v4.7.2-stable_linux.x86_64"; return 0
  fi
  echo ""
}

GODOT="$(find_godot)"
if [ -z "$GODOT" ]; then
  echo "No encuentro Godot 4.7.2 para Linux. Instala el editor o define GODOT_BIN=/ruta/al/binario" >&2
  exit 1
fi
echo "Usando Godot: $GODOT"

TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/4.7.2.stable"
if [ ! -d "$TEMPLATES_DIR" ]; then
  echo "Aviso: no veo $TEMPLATES_DIR — la exportación fallará si faltan las plantillas." >&2
fi

# --- 1. Importar y exportar ---
rm -rf "$OUT"
mkdir -p "$OUT"
echo "1/4 Importando recursos..."
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null
echo "2/4 Exportando Linux..."
"$GODOT" --headless --path "$ROOT/game" --export-release "Linux" "$OUT/$BIN"
[ -f "$OUT/$BIN" ] || { echo "La exportación no produjo $BIN" >&2; exit 1; }
chmod +x "$OUT/$BIN"

# --- 2. Copiar datos públicos ---
echo "3/4 Copiando datos públicos..."
for rel in content/public content/generated contract/fixtures assets_generated/portraits; do
  mkdir -p "$OUT/$rel"
  if [ -d "$ROOT/$rel" ]; then
    cp -R "$ROOT/$rel/." "$OUT/$rel/"
  fi
done

# --- 3. Lanzadores y LEEME ---
cat > "$OUT/Jugar con el motor.sh" <<'SH'
#!/usr/bin/env bash
# Requiere el motor corriendo: python3 -m server (desde la raíz del repo)
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/LeyendasSV.x86_64" -- --backend=http --api=http://127.0.0.1:8000
SH
cat > "$OUT/Jugar sin motor (demo).sh" <<'SH'
#!/usr/bin/env bash
# Modo mock: respuestas de ejemplo, sin IA ni internet.
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/LeyendasSV.x86_64" -- --backend=mock
SH
cat > "$OUT/LEEME.txt" <<'EOF'
Leyendas SV: El Último Rezo de las Ánimas (v1.0, Linux x86_64)

- "Jugar con el motor.sh": la versión completa, con testigos de IA y voz.
  Antes, desde la raíz del repo: .venv/bin/python -m server
- "Jugar sin motor (demo).sh": respuestas de ejemplo, sin internet.
- LeyendasSV.x86_64 a secas usa el modo guardado en Opciones.

Dependencias del sistema (presumiblemente ya instaladas en un escritorio):
  libx11-6 libgl1 libasound2 (Ubuntu/Debian)

Controles: clic o WASD/flechas para caminar; clic o E para hablar y examinar;
Tab o el botón Diario; Esc o el botón Pausa.
En el interrogatorio: escribe, elige una pregunta sugerida o pulsa "Hablar"
(o F1) y haz tu pregunta en voz alta; al hacer una pausa se envía sola.
Créditos de retratos y personajes: assets_generated/portraits/CREDITOS.md
EOF
chmod +x "$OUT/Jugar con el motor.sh" "$OUT/Jugar sin motor (demo).sh"

# --- 4. Comprimir (y AppImage opcional) ---
echo "4/4 Comprimiendo..."
rm -f "$TARGZ"
tar -C "$ROOT/game/export" -czf "$TARGZ" "LeyendasSV"
echo "  $(du -h "$TARGZ" | cut -f1)  $TARGZ"

if [ "${1:-}" = "--appimage" ]; then
  echo "Generando AppImage..."
  if command -v appimagetool >/dev/null 2>&1; then
    APPDIR="$ROOT/game/export/AppDir"
    rm -rf "$APPDIR"
    mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/512x512/apps"
    cp "$OUT/$BIN" "$APPDIR/usr/bin/LeyendasSV"
    cp "$OUT/$BIN" "$APPDIR/LeyendasSV"
    cp -R "$OUT/content" "$OUT/contract" "$OUT/assets_generated" "$APPDIR/"
    cat > "$APPDIR/LeyendasSV.desktop" <<'DESK'
[Desktop Entry]
Name=Leyendas SV: El Último Rezo de las Ánimas
Comment=Juego de investigación sobrenatural en San Jacinto de las Ánimas
Exec=LeyendasSV
Icon=leyendas-sv
Terminal=false
Type=Application
Categories=Game;
DESK
    cp "$APPDIR/LeyendasSV.desktop" "$APPDIR/usr/share/applications/"
    # Icono: generar PNG 512 desde el SVG si hay rsvg/convert; si no, reutilizar retrato neutral como temporal.
    if command -v rsvg-convert >/dev/null 2>&1; then
      rsvg-convert -w 512 -h 512 "$ROOT/game/icon.svg" -o "$APPDIR/usr/share/icons/hicolor/512x512/apps/leyendas-sv.png"
    elif command -v convert >/dev/null 2>&1; then
      convert -background none "$ROOT/game/icon.svg" "$APPDIR/usr/share/icons/hicolor/512x512/apps/leyendas-sv.png"
    else
      echo "Aviso: sin rsvg-convert ni ImageMagick, el icono PNG no se generará; copia game/icon.png manualmente." >&2
      cp "$ROOT/game/icon.svg" "$APPDIR/usr/share/icons/hicolor/512x512/apps/leyendas-sv.svg" 2>/dev/null || true
    fi
    cp "$APPDIR/usr/share/icons/hicolor/512x512/apps/"*.png "$APPDIR/.DirIcon" 2>/dev/null || cp "$ROOT/game/icon.svg" "$APPDIR/.DirIcon" 2>/dev/null || true
    cat > "$APPDIR/AppRun" <<'RUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/LeyendasSV" "$@"
RUN
    chmod +x "$APPDIR/AppRun" "$APPDIR/LeyendasSV" "$APPDIR/usr/bin/LeyendasSV"
    rm -f "$APPIMAGE"
    ARCH=x86_64 appimagetool "$APPDIR" "$APPIMAGE"
    chmod +x "$APPIMAGE"
    rm -rf "$APPDIR"
    echo "  $(du -h "$APPIMAGE" | cut -f1)  $APPIMAGE"
  else
    echo "Aviso: appimagetool no está instalado; instala appimaged o el binario de AppImageKit para usar --appimage." >&2
  fi
fi
echo "Listo."
