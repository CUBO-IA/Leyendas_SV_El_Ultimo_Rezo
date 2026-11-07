# Leyendas SV: El Último Rezo de las Ánimas

Juego de investigación sobrenatural ambientado en **San Jacinto de las Ánimas, El Salvador**, la víspera del Día de los Difuntos. Nueve vecinos han desaparecido y solo queda una noche para resolverlo.

El jugador explora el pueblo, interroga a testigos controlados por IA (con voz), les presenta evidencias para descubrir sus mentiras y acusa a **1 de 6 entidades** antes de la última campanada. Hay **3 finales**: malo, gris y verdadero.

> Historia completa: [`docs/historia.md`](docs/historia.md) · Prompts de fases: [`docs/prompts_claude_code.md`](docs/prompts_claude_code.md)

## Características

- **Motor de interrogatorio** por HTTP + JSON con reglas deterministas y LLM solo para redactar respuestas.
- **Voz completa**: testigos con voz Magpie TTS (ES-US, cambia por emoción) y entrada de voz del jugador por STT (Riva/Parakeet). Si la voz falla, el juego sigue en texto.
- **10 testigos** (Chonita, Chepe, Chente, Ramírez, Padre Mauricio, Toñito, Beto, Pilo, Alcides, Mercedes) y **6 sospechosos** (Cipitío, Siguanaba, Cadejo, Padre Sin Cabeza, Carreta Chillona, Descarnada).
- **Modo demo sin motor**: backend `mock` que responde con los fixtures del contrato.
- **Testigos que no inventan**: el prompt les da solo lo que saben y un verificador corrige nombres u horas inventados.
- **Fácil de jugar**: clic o teclado para caminar e interactuar; micrófono de un clic (se corta solo al callarte) y preguntas sugeridas.
- **Build de Windows**: `.exe` autocontenido para el cliente; el motor se corre aparte (ver abajo).

## Arquitectura

```text
Godot 4.7.2 (game/) ──HTTP/JSON──► FastAPI (server/) ──► NVIDIA API / Ollama
                                    │
                                    └─ único que conoce la solución (server/data/)
```

- **Cliente** (`game/`): GDScript, Godot 4.7.2. Solo habla con el motor en `API_BASE_URL` (`http://127.0.0.1:8000`).
- **Motor** (`server/`): Python 3.12 + FastAPI. `rules.py` decide niveles, evidencias, actos y finales; `dialogue.py` solo redacta con el LLM.
- **Contrato** (`contract/`): JSON Schema como fuente de verdad + fixtures válidos.

Endpoints: `GET /health`, `POST /session`, `GET /session/{id}`, `POST /talk`, `POST /present`, `POST /examine`, `POST /accuse`, `POST /stt`, `GET /audio/{id}.mp3`.

## Estructura del repositorio

```text
.
├── game/                  # Cliente Godot (abrir game/project.godot)
├── server/                # Motor FastAPI + pipelines (personas, retratos, voz)
├── contract/              # schemas/*.schema.json + fixtures/*.json
├── content/public/        # Datos públicos (world, evidence, characters)
├── assets_generated/      # Retratos 512x512 (portraits/) y arte del equipo (personajes/, fachadas/)
├── tests/                 # Pruebas de contrato y del motor
├── tools/                 # Scripts: smoke tests, placeholders, SFX, build
├── docs/                  # Historia y prompts de fases
└── CLAUDE.md              # Guía de trabajo para contribuidores
```

## Requisitos

| Herramienta | Versión | Notas |
|---|---|---|
| Godot | 4.7.2 (estándar) | Abrir `game/project.godot` |
| Python | 3.12 | Entorno en `.venv/` |
| NVIDIA API | — | Clave en `.env` (ver `.env.example`). Alternativa offline: Ollama local con `nemotron-3-nano:4b` |

## Cómo ejecutar

### 1. Motor (terminal 1)

```powershell
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r server/requirements.txt
copy .env.example .env   # y completa NVIDIA_API_KEY
.venv\Scripts\python -m server
```

### 2. Cliente Godot (terminal 2, opcional)

1. Abre Godot → **Project → Import** → selecciona `game/project.godot`.
2. Pulsa **F5** (ejecutar). Por defecto usa el backend `mock`; para jugar contra el motor real, en **Opciones** cambia a backend `http` o ejecuta con `-- --backend=http`.

### 3. Build de Windows

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1
```

Genera `game\export\LeyendasSV\` y `LeyendasSV-windows.zip` (requiere las plantillas de exportación de Godot 4.7.2). Dentro vienen dos lanzadores: **Jugar con el motor.bat** (con el motor corriendo, IA y voz) y **Jugar sin motor (demo).bat** (modo mock, sin internet). El `.exe` no incluye el motor ni la solución del caso.

### 4. Pruebas

```powershell
.venv\Scripts\python -m pytest tests/contract -q   # contrato + fixtures
.venv\Scripts\python -m pytest tests -q            # motor completo
.venv\Scripts\python tools\smoke_game.py           # recorrido real por HTTP (motor corriendo)
```

Prueba headless del cliente:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/smoke_test.tscn
```

## Créditos

- Fichas de personajes basadas en el dataset *Nemotron-Personas-El-Salvador* de NVIDIA (CC BY 4.0) — ver [`server/CREDITS.md`](server/CREDITS.md).
- Retratos de testigos: arte de referencia del equipo (fescobar85) recortado a busto 512×512; sospechosos: pixel art procedural — ver [`assets_generated/portraits/CREDITOS.md`](assets_generated/portraits/CREDITOS.md).
- Música, viento, campanadas y SFX sintetizados con `tools/make_sfx.py` (sin licencias).

## Licencia

Este proyecto se distribuye bajo licencia **MIT** — ver [`LICENSE`](LICENSE).

## Contribuir

Lee [`CLAUDE.md`](CLAUDE.md) antes de enviar cambios: un commit por fase, nunca subir `.env` ni claves, y cualquier cambio en `contract/` debe actualizar fixtures y correr `tests/contract`.
