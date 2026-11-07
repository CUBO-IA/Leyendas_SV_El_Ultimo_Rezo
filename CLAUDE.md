# Leyendas SV: El Último Rezo de las Ánimas

## Qué es
Juego de investigación sobrenatural en Godot 4.7.2 (GDScript), ambientado en San Jacinto de las Ánimas, El Salvador, la víspera del Día de los Difuntos. El jugador interroga testigos controlados por IA, les presenta evidencias para descubrir sus mentiras y acusa a 1 de 6 entidades. La historia completa está en docs/historia.md. Hackathon de 2 días, equipo de 2 ingenieros en paralelo.

## Equipo y máquina (cambio de plan)
- Un solo desarrollador hace el trabajo de los dos roles (A: Godot, B: motor) en UNA laptop: Ryzen AI 9 365, Radeon 880M integrada (sin NVIDIA/CUDA), 32 GB de RAM, Windows 11.
- Las carpetas se mantienen separadas por capa (no por persona): game/ = cliente; server/, tools/ = motor; contract/ = la frontera entre los dos. Un cambio en contract/ exige actualizar fixtures y correr tests/contract.

## Arquitectura
- Godot (cliente) habla SOLO con el motor por HTTP + JSON en API_BASE_URL (http://127.0.0.1:8000, todo en la misma laptop).
- Motor: Python 3.12 + FastAPI. Es el único que llama a modelos de IA y el único que conoce la solución del caso (server/data/). La solución nunca se copia al cliente.
- Diálogo: se elige por .env tras la prueba de latencia de B1 (meta < 3 s). Opción 1: API de NVIDIA (build.nvidia.com, compatible con OpenAI). Opción 2: Ollama local con nemotron-3-nano:4b en CPU/iGPU (think=false, JSON con esquema). La que no gane queda de respaldo.
- Decisión B1 (tools/smoke_llm.py, 10 preguntas a Chonita): gana la API de NVIDIA con nvidia/nemotron-3.5-lightning-30b-a3b (mediana 0.7 s, emociones variadas). nvidia/nemotron-3.5-bolt-e4b es la alternativa rápida; Ollama local (mediana 4.6 s) es el respaldo sin internet. La API acepta JSON por response_format json_schema (no guided_json); nvidia/nemotron-nano-3-30b-a3b da 404 en esta cuenta.
- Voz de los NPC: Magpie TTS Multilingual (API de NVIDIA), MP3. Respaldo: Piper es_MX (CPU).
- Voz del jugador a texto: Nemotron 3.5 Transcribe (API alojada). Respaldo: faster-whisper small (CPU).
- Personajes: dataset nvidia/Nemotron-Personas-El-Salvador -> fichas JSON -> retratos. Sin GPU NVIDIA, SDXL local no es viable: los retratos se generan con una API de imágenes en la nube o se reduce a 1-2 emociones por personaje (se decide en B5). Los placeholders siempre funcionan.
- Godot también tiene un Backend "mock" (responde con contract/fixtures/) para probar el cliente sin el motor y como plan B en la demo.

## Contrato
- contract/schemas/*.schema.json (JSON Schema) es la fuente de verdad. contract/fixtures/*.json son respuestas de ejemplo válidas.
- Fixtures: se llaman `{schema}__{variante}.json` y validan contra `contract/schemas/{schema}.schema.json`.
- Solo cambios que suman: un campo nuevo siempre es opcional.
- Rutas: GET /health, POST /session, GET /session/{id}, POST /talk, POST /present, POST /examine, POST /accuse, POST /stt, GET /audio/{id}.mp3
- Las deducciones viajan como objetos {id, text}: su texto vive solo en el servidor, así el cliente no lleva spoilers.

## IDs y archivos fijos
- Testigos: chonita, chepe, chente, ramirez, padre_mauricio, tonito, beto, pilo, alcides, mercedes
- Sospechosos: cipitio, siguanaba, cadejo, padre_sin_cabeza, carreta_chillona, descarnada
- Emociones: neutral, nervioso, enojado, asustado, triste, aliviado
- Niveles de interrogatorio: inicial, confrontada, confesion
- Retratos: assets_generated/portraits/{id}_{emocion}.png, 512x512. Si no existe la emoción, Godot usa {id}_neutral.png; si tampoco existe, game/assets/placeholders/.
- Datos públicos: content/public/{world,evidence,characters}.json. Datos secretos: server/data/{case_secret,endings}.json.

## Alcance
- MVP: Acto I y Acto III; 6 testigos (chonita, tonito, ramirez, padre_mauricio, alcides, mercedes); 6 sospechosos; 3 finales (malo, gris, verdadero).
- Extras, en este orden: voz, Acto II (cementerio y quebrada), los 4 testigos restantes, sistema de miedo, campanadas por tiempo.

## Orden de fases (un desarrollador, una laptop)
Los prompts originales de cada fase están en docs/prompts_claude_code.md. Se intercalan así para tener algo jugable cuanto antes:
1. Fase 0 — contrato y datos del caso (hecha).
2. B1 — motor base, proveedor LLM y prueba de latencia (decide API de NVIDIA vs. Ollama local).
3. A1 — esqueleto Godot con Backend mock/http.
4. B3 — /talk, /present, /examine, /accuse (reglas deterministas + LLM solo redacta).
5. A2 — el pueblo (Acto I).
6. A3 — interrogatorio. → Unión 1: hablar con Chonita y quebrar a Alcides contra el motor real.
7. A4 — diario, campanario, acusación y finales. → Unión 2 (v0.9): partida completa.
8. B2 — fichas desde Nemotron-Personas-El-Salvador.
9. B4 + A5 — voz (STT/TTS) y pulido.
10. B5 — retratos. → Unión final (v1.0).

## Cómo trabajar
- Una fase a la vez. Al terminar: probar, darme el comando de prueba y el mensaje de commit, y esperar "siguiente fase".
- Windows 11. Explica en español, paso a paso, el porqué antes de actuar.
- Rama main; un commit por fase y etiquetas v0.1 / v0.9 / v1.0 en las uniones.
- Nunca subas .env ni claves de API.
- Pruebas de contrato: `.venv\Scripts\python -m pytest tests/contract -q` (dependencias en tests/requirements.txt).

## Entorno local
- Python 3.12.10 en .venv (raíz del repo). Crear con `py -3.12 -m venv .venv`.
- Godot 4.7.2 (estándar) instalado por winget en %LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\. Para leer errores sin el MCP, usar Godot_v4.7.2-stable_win64_console.exe con --path game.
- Ollama 0.40 local; claves solo en .env (ignorado por git).
- Motor: `.venv\Scripts\python -m server` (lee .env). Pruebas del motor: `.venv\Scripts\python -m pytest tests -q`.
- Recorrido real por HTTP (Chonita + quebrar a Alcides): `.venv\Scripts\python tools\smoke_game.py` con el motor corriendo.
- Motor por capas: rules.py decide (niveles, evidencias, actos, finales); dialogue.py solo redacta con el LLM (memoria, filtros, caché, respaldo a los LLM_REPLY_TIMEOUT_S).
- Cliente: prueba headless `Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/smoke_test.tscn` (agregar `-- --backend=http` con el motor corriendo). Tras agregar PNG o class_name nuevos: `--headless --path game --import`.
- Godot lee content/, contract/fixtures/ y assets_generated/ directo de la raíz del repo (res://..), sin copias. Modo del Backend y URL: Opciones (user://settings.cfg) o `-- --backend=http --api=URL`.
- Placeholders: `.venv\Scripts\python tools\make_placeholders.py` (Pillow, tools/requirements.txt).
- Arte de interiores (iglesia, campanario) y fondos de finales: `.venv\Scripts\python tools\make_story_art.py`.
- Recorrido visual de A4 (pueblo en acto 3, iglesia, diario, acusación, final): `Godot --path game res://tests/visual_tour.tscn`.
- Escenas a pie: game/scripts/explore/explore_base.gd (HUD, E, Tab, puertas); el pueblo y los interiores solo arman su mapa.
- Fichas de personajes (B2): `.venv/Scripts/python -m server.pipelines.personas` (`--dry-run` para ver candidatos, `--only id --force` para regenerar). Descarga 1 parquet de Nemotron-Personas-El-Salvador (190 MB, caché de HF) y escribe server/data/characters/, content/generated/characters_public.json y server/CREDITS.md. Al LLM no se le pasa la pista ni la mentira; la voz Magpie concreta se asigna en B4 (voice.voice = null).
- Sonidos sintetizados (sin licencias): `.venv\Scripts\python tools\make_sfx.py` -> game/assets/sfx/.
- Arte del pueblo (baldosas, fachadas, sprites 16x24 en 4 direcciones): `.venv\Scripts\python tools\make_town_art.py`, y después `--import`. El plano está en game/scripts/town/town_layout.gd; los objetos de un lugar solo aparecen cuando el motor lo desbloquea.
