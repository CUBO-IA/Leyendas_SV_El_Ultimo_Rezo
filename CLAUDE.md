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
- Decisión B4: Magpie TTS y el reconocedor van por gRPC (Riva, `nvidia-riva-client`) en grpc.nvcf.nvidia.com con la misma NVIDIA_API_KEY; la API de chat no tiene /audio. Voces ES-US por testigo en server/app/voice.py (Isabela y Diego cambian por emoción). STT: parakeet-1_1b-rnnt-multilingual (parakeet-ctc-0_6b-es no tenía servidores el 2026-11-06; queda segundo en ASR_FUNCTION_IDS). Nemotron 3.5 Transcribe exige cuenta aparte (DeepInfra/Baseten). Respaldos locales (Piper, faster-whisper) no instalados: si la voz falla el juego sigue con texto.
- Voz del jugador a texto: Nemotron 3.5 Transcribe (API alojada). Respaldo: faster-whisper small (CPU).
- Personajes: dataset nvidia/Nemotron-Personas-El-Salvador -> fichas JSON -> retratos. Sin GPU NVIDIA, SDXL local no es viable: los retratos se generan con una API de imágenes en la nube o se reduce a 1-2 emociones por personaje (se decide en B5). Los placeholders siempre funcionan.
- Decisión B5: retratos en assets_generated/portraits con `.venv\Scripts\python -m server.pipelines.portraits`. Testigos: arte del equipo (assets_generated/personajes, fescobar85) recortado a busto; cada uno trae una emoción y es también su neutral (las demás caen al neutral). Sospechosos: pixel art procedural. Las APIs de imagen de build.nvidia.com no sirvieron el 2026-11-06 (FLUX Kontext solo acepta imágenes de ejemplo; FLUX schnell/dev: timeout y 500). Nayik.png no se usa (no es del elenco y parece caricatura de una persona real).
- Godot también tiene un Backend "mock" (responde con contract/fixtures/) para probar el cliente sin el motor y como plan B en la demo.

## Contrato
- contract/schemas/*.schema.json (JSON Schema) es la fuente de verdad. contract/fixtures/*.json son respuestas de ejemplo válidas.
- Fixtures: se llaman `{schema}__{variante}.json` y validan contra `contract/schemas/{schema}.schema.json`.
- Solo cambios que suman: un campo nuevo siempre es opcional.
- Rutas: GET /health, POST /session, GET /session/{id}, POST /talk, POST /present, POST /examine, POST /accuse, POST /stt, GET /audio/{id}.mp3
- Las deducciones viajan como objetos {id, text}: su texto vive solo en el servidor, así el cliente no lleva spoilers.
- POST /stt recibe el WAV crudo en el cuerpo (Content-Type: audio/wav, 16 bits, máx. 30 s) y responde stt_response. El audio de /talk y /present se sintetiza en segundo plano: GET /audio/{id}.mp3 espera si aún no termina.

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
- Hecho: los 4 testigos restantes (beto, pilo, chente, chepe) están en la partida por defecto (WITNESSES=all en .env; WITNESSES=mvp vuelve a 6). Van después de los 6 del MVP en WorldState.npcs (server/app/data.py ORDER); las fixtures siguen describiendo la partida MVP. Sus pistas apuntan a las otras leyendas y ningún final las exige; Chepe necesita la quebrada (acto 2). El mock agrega los 4 a la fixture de sesión.

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
- Testigos sin inventar: el prompt lista la gente, lugares y leyendas del pueblo (sin el culpable) y prohíbe nombres, horas y sucesos fuera de la guía; los nombres de los 9 desaparecidos no se dicen. server/app/llm/grounding.py detecta horas y nombres propios que no están en el prompt ni en lo que dijo el jugador: dialogue.py pide una corrección y, si insiste, quita esas frases (o usa el respaldo). Temperatura 0.5. Medición: `.venv\Scripts\python tools\eval_grounding.py [--dialogue]` (50 preguntas trampa; antes 39 % inventaba, ahora 0 %).
- Cliente: prueba headless `Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/smoke_test.tscn` (agregar `-- --backend=http` con el motor corriendo). Tras agregar PNG o class_name nuevos: `--headless --path game --import`.
- Godot lee content/, contract/fixtures/ y assets_generated/ directo de la raíz del repo (res://..), sin copias. Modo del Backend y URL: Opciones (user://settings.cfg) o `-- --backend=http --api=URL`.
- Placeholders: `.venv\Scripts\python tools\make_placeholders.py` (Pillow, tools/requirements.txt).
- Arte de interiores (iglesia, campanario) y fondos de finales: `.venv\Scripts\python tools\make_story_art.py`.
- Recorrido visual de A4 (pueblo en acto 3, iglesia, diario, acusación, final): `Godot --path game res://tests/visual_tour.tscn`.
- Escenas a pie: game/scripts/explore/explore_base.gd (HUD, E o clic, Tab, puertas); el pueblo y los interiores solo arman su mapa. Clic en el suelo = caminar (TownPlayer.walk_to); clic en testigo/objeto/puerta = caminar y usarlo. El HUD tiene botones Diario y Pausa.
- Fichas de personajes (B2): `.venv/Scripts/python -m server.pipelines.personas` (`--dry-run` para ver candidatos, `--only id --force` para regenerar). Descarga 1 parquet de Nemotron-Personas-El-Salvador (190 MB, caché de HF) y escribe server/data/characters/, content/generated/characters_public.json y server/CREDITS.md. Al LLM no se le pasa la pista ni la mentira; la voz Magpie concreta se asigna en B4 (voice.voice = null).
- Voz en vivo: `.venv\Scripts\python tools\smoke_game.py --voice` (mide texto + voz y prueba /stt). En el interrogatorio se habla con el botón Hablar (o F1 / Ctrl+Espacio): un clic empieza, VoiceActivity (game/scripts/voice_activity.gd) corta tras ~1 s de silencio y la pregunta se envía sola (Opciones: «Revisar antes de enviar» la deja en la caja). Tab abre el diario encima. Hay preguntas sugeridas sin spoilers. Chequeo del micrófono real (con ventana): `Godot --path game res://tests/mic_check.tscn -- --backend=http`. El motor descarta transcripciones sin letras latinas (el modelo multilingüe "oye" ruso en el ruido). Audio del cliente: autoload Sound (buses, ambiente, voz MP3, micrófono); salir con Sound.quit_clean().
- Sonidos sintetizados (sin licencias): `.venv\Scripts\python tools\make_sfx.py` -> game/assets/sfx/ (incluye latido y susurro).
- Rama experimental/multijugador: presencia compartida. Los jugadores conectados al mismo motor se ven moverse en el mapa (WebSocket /ws/presence en server/app/presence.py; autoload Presence + RemotePlayer en Godot). Solo viaja escena, posición y hacia dónde mira; cada uno sigue con su partida. Solo en modo http. Nombre y casilla en Opciones (o `-- --name=Fer`). Bot de prueba: `.venv/Scripts/python tools/presence_bot.py`. Build aparte: `tools/build_windows.ps1 -Name LeyendasSV-exp`.
- Juego en red (cada computadora su partida): `powershell -ExecutionPolicy Bypass -File tools\motor_en_red.ps1` pone API_HOST=0.0.0.0 solo para ese proceso (no toca .env), muestra las IP y avisa si la red es Pública (firewall). Clientes: 'Jugar en red.bat' del build (pide la IP). Carga: `.venv\Scripts\python tools\smoke_lan.py --api http://IP:8000 --players 8` (2026-11-07: 8 a la vez, 0 errores, sin 429).
- Acto II: el cementerio es una sala (InteriorLayout.ROOMS["cementerio"], al aire libre: carpet_tile, windows, dim, fog) a la que se entra por el portón del pueblo (TownLayout.DOORS, cerrado hasta el acto II); ahí están tumba_sin_nombre y muro_cementerio. Arte con `.venv\Scripts\python tools\make_story_art.py --interior`. Niebla (FogOverlay) en el pueblo desde el acto II y en el cementerio; tarjeta de cada acto (ActCard, una vez por acto: GameState.act_card_seen). Ver una sala: visual_tour `-- --interior=cementerio`.
- Vecinos de ambiente: content/public/villagers.json (nombre, oficio, spot en baldosas, look = colores del sprite, frases por acto). Sprites con `.venv\Scripts\python tools\make_town_art.py --chars`. Clase Villager (pasea cerca de su lugar); E o clic -> MessageBox con la siguiente frase del acto (GameState.chatter). Sin motor ni IA.
- La noche (autoload Night, solo cliente): reloj vivo (1 min de juego cada 12 s reales en las escenas a pie, sin pasar de la hora del acto siguiente: ACT_CAP), campanadas en cada cuarto y a la hora en punto (12 a medianoche) y miedo del jugador 0-100 (sube con el tiempo, las campanadas, el cambio de acto y en cementerio/quebrada/campanario; baja junto a faroles y velas y en la iglesia). Efectos: barra en el HUD, viñeta FearOverlay, latido desde 55 y susurros desde 80. GameState.clock_text() sigue siendo la hora del motor; el HUD usa Night.clock_text(). Ver con miedo alto: visual_tour `-- --fear=90 --spawn=x,y`.
- Build de Windows (v1.0): `powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1` -> game\export\LeyendasSV\ (exe con pck incrustado + content\, contract\fixtures\, assets_generated\portraits\ y dos .bat: con motor / sin motor) y LeyendasSV-windows.zip. Plantillas 4.7.2 en %APPDATA%\Godot\export_templates\4.7.2.stable (solo las de Windows). El build excluye tests/ y nunca lleva server\ ni .env.
- Arte del pueblo (baldosas, fachadas, sprites 16x24 en 4 direcciones): `.venv\Scripts\python tools\make_town_art.py`, y después `--import`. Las fachadas que se ven son las del equipo (assets_generated/fachadas, fescobar85): `.venv\Scripts\python tools\import_facades.py [--preview]` les quita cielo y suelo (recuadro por edificio en BOXES) y escribe game/assets/town/facades_hd/ al triple del ancho del lote; town.gd las dibuja a escala 1/3 con la base del lote procedural (puertas y objetos no se mueven). Si falta una, usa la procedural. El plano está en game/scripts/town/town_layout.gd; los objetos de un lugar solo aparecen cuando el motor lo desbloquea.
