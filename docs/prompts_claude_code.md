# Leyendas SV: El Último Rezo — Prompts para Claude Code (Godot)

Nov 6, 2026 · @Que puedes hacer ?

## 1. Antes de empezar: qué hace cada modelo

Los dos modelos de NVIDIA que eligieron sirven, pero ninguno hace imágenes ni voz de personajes. Nemotron-Personas da las biografías y Nemotron 3.5 Transcribe convierte la voz del jugador en texto. Para la voz de los NPC se agrega Magpie TTS, también de NVIDIA.

| Modelo | Qué es en realidad | Para qué lo usamos | Dónde corre |
| --- | --- | --- | --- |
| [Nemotron-Personas-El-Salvador](https://huggingface.co/collections/nvidia/nemotron-personas) | Dataset de texto: unos 148 mil registros y 1 millón de personas sintéticas en español salvadoreño, basado en el censo 2024, licencia CC BY 4.0. No trae imágenes ni audio. | Biografía, forma de hablar y rasgos realistas de cada testigo; de ahí sale su ficha y el prompt visual de su retrato | Script Python offline (Ingeniero B) |
| [Nemotron 3.5 Transcribe 30B-A4B](https://www.eesel.ai/blog/nemotron-3-5-transcribe) | Voz a texto en 40 idiomas, publicado el 28 de octubre de 2026. Convierte audio en texto; no genera voz. | Que el jugador le hable al testigo con el micrófono | API alojada, unos US$0.002 por minuto. En BF16 pide cerca de 80 GB de VRAM: no cabe en 12 GB |
| [Magpie TTS Multilingual](https://build.nvidia.com/nvidia/magpie-tts-multilingual) (se agrega) | Texto a voz de NVIDIA con voces en español y variantes por emoción | La voz de cada NPC | API gratuita de desarrollo en build.nvidia.com; Piper local como respaldo |
| Nemotron 3 Nano 4B (se mantiene) | Modelo de lenguaje | Lo que dice cada testigo | Ollama, GPU local |
| SDXL en ComfyUI (se mantiene) | Generador de imágenes | Retratos desde el prompt visual de cada persona | GPU local, por lotes |

**Conectar Claude Code con Godot** (solo lo necesita el Ingeniero A):

1. Instalar Godot 4.7.2, la versión estándar (no la .NET), porque el juego va en GDScript.
2. Instalar Node.js 18 o superior.
3. En una terminal: `claude mcp add godot -e GODOT_PATH="C:\ruta\a\Godot.exe" -e DEBUG=true -- npx @coding-solo/godot-mcp`
4. Abrir Claude Code en la carpeta del repositorio y escribir `/mcp` para confirmar que `godot` aparece conectado.

Con esto, Claude Code puede abrir el editor, correr el proyecto, leer los errores de depuración y crear escenas y nodos. Escribe los archivos `.gd` y `.tscn` directamente, y usa el MCP para probar y corregirse solo.

Fuentes: [Godot MCP (Coding-Solo)](https://github.com/Coding-Solo/godot-mcp) · [Nemotron-Personas-El-Salvador](https://hyper.ai/en/datasets/53369) · [Requisitos de Nemotron 3.5 Transcribe](https://ai-bot.cn/nemotron-3-5-transcribe/) · [Precio de Transcribe en DeepInfra](https://deepinfra.com/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B) · [Voces en español de Magpie](https://docs.nvidia.com/deeplearning/riva/user-guide/docs/tts/tts-overview.html)

## 2. Arquitectura

Godot corre en cualquier laptop y solo habla con el motor Python por la red local. El motor vive en la PC con la RTX, es el único que usa los modelos y el único que conoce la solución del caso. Así es la arquitectura de su dibujo, con el contrato en medio.

&#91;embedded content: arquitectura · Godot, motor y modelos de NVIDIA\]

Godot 2D corre bien en la laptop AMD con gráficos integrados, así que la RTX queda libre para Ollama y ComfyUI.

## 3. Reparto sin choques y alcance

Cada ingeniero tiene sus carpetas, su máquina y sus fases. Solo se juntan en la Fase 0 y en las uniones.

&#91;embedded content: fases · 2 carriles, 3 uniones\]

| Carpeta | Dueño |
| --- | --- |
| `game/` | Ingeniero A |
| `server/`, `tools/`, `content/generated/`, `assets_generated/` | Ingeniero B |
| `contract/`, `content/public/`, `docs/`, `tests/contract/`, `CLAUDE.md` | Los dos: se crean en la Fase 0 y después solo cambian por acuerdo |

**Cómo se evita depender del otro:**

1. **Contrato con ejemplos:** A programa contra un Backend simulado que responde con `contract/fixtures/`. B valida sus respuestas contra los mismos `contract/schemas/`. Al unir, A cambia una opción de mock a http.
2. **Nombres de archivo fijos:** los retratos se llaman `{id}_{emocion}.png`. A usa placeholders mientras tanto; cuando B genera los reales, aparecen solos sin tocar código.
3. **Datos públicos y secretos separados:** `content/public/` lo leen los dos; la solución vive solo en `server/data/`, así el cliente no puede revelar el culpable.
4. **Máquinas separadas:** B trabaja en la PC con la RTX (Ollama y ComfyUI); A en cualquier laptop con Godot.

**Alcance para 2 días:** la historia completa (10 testigos, 3 actos, miedo, campanadas por tiempo) no entra en un hackathon. El MVP es el Acto I más el Acto III con 6 testigos: Doña Chonita, Toñito, Agente Ramírez, Padre Mauricio, Don Alcides y Niña Mercedes. Son los que sostienen las pruebas de la solución y el ejemplo de interrogatorio. Los 6 sospechosos sí están completos en la acusación. El Acto II y los otros 4 testigos son el primer extra.

## 4. CLAUDE.md compartido

Claude Code lee automáticamente el archivo `CLAUDE.md` de la raíz del repositorio en cada sesión. Los dos lo tienen igual; así los dos chats trabajan con el mismo contexto y las mismas reglas. Guarden también la historia como `docs/historia.md`.

```markdown
# Leyendas SV: El Último Rezo de las Ánimas

## Qué es
Juego de investigación sobrenatural en Godot 4.7.2 (GDScript), ambientado en San Jacinto de las Ánimas, El Salvador, la víspera del Día de los Difuntos. El jugador interroga testigos controlados por IA, les presenta evidencias para descubrir sus mentiras y acusa a 1 de 6 entidades. La historia completa está en docs/historia.md. Hackathon de 2 días, equipo de 2 ingenieros en paralelo.

## Propiedad de carpetas (no se cruza)
- Ingeniero A: game/ (proyecto Godot).
- Ingeniero B: server/, tools/, content/generated/, assets_generated/.
- Compartido, solo se cambia en pareja: contract/, content/public/, docs/, tests/contract/, CLAUDE.md.
- Nunca edites carpetas del otro rol. Si necesitas un cambio en una carpeta compartida, propónlo y detente.

## Arquitectura
- Godot (cliente) habla SOLO con el motor por HTTP + JSON en API_BASE_URL (por defecto http://127.0.0.1:8000; en la demo, la IP de la PC con RTX en la red local).
- Motor: Python 3.12 + FastAPI. Es el único que llama a modelos de IA y el único que conoce la solución del caso (server/data/). La solución nunca se copia al cliente.
- Diálogo: Ollama con nemotron-3-nano:4b (think=false, salida JSON con esquema). Respaldo: API de NVIDIA.
- Voz de los NPC: Magpie TTS Multilingual (API de NVIDIA), MP3. Respaldo: Piper es_MX.
- Voz del jugador a texto: Nemotron 3.5 Transcribe (API alojada). Respaldo: faster-whisper small.
- Personajes: dataset nvidia/Nemotron-Personas-El-Salvador -> fichas JSON -> retratos con SDXL en ComfyUI.

## Contrato
- contract/schemas/*.schema.json (JSON Schema) es la fuente de verdad. contract/fixtures/*.json son respuestas de ejemplo válidas.
- Solo cambios que suman: un campo nuevo siempre es opcional.
- Rutas: GET /health, POST /session, GET /session/{id}, POST /talk, POST /present, POST /examine, POST /accuse, POST /stt, GET /audio/{id}.mp3

## IDs y archivos fijos
- Testigos: chonita, chepe, chente, ramirez, padre_mauricio, tonito, beto, pilo, alcides, mercedes
- Sospechosos: cipitio, siguanaba, cadejo, padre_sin_cabeza, carreta_chillona, descarnada
- Emociones: neutral, nervioso, enojado, asustado, triste, aliviado
- Niveles de interrogatorio: inicial, confrontada, confesion
- Retratos: assets_generated/portraits/{id}_{emocion}.png, 512x512. Si no existen, Godot usa game/assets/placeholders/.

## Alcance
- MVP: Acto I y Acto III; 6 testigos (chonita, tonito, ramirez, padre_mauricio, alcides, mercedes); 6 sospechosos; 3 finales (malo, gris, verdadero).
- Extras, en este orden: voz, Acto II (cementerio y quebrada), los 4 testigos restantes, sistema de miedo, campanadas por tiempo.

## Cómo trabajar
- Una fase a la vez. Al terminar: probar, darme el comando de prueba y el mensaje de commit, y esperar "siguiente fase".
- Windows 11. Explica en español, paso a paso, el porqué antes de actuar.
- Ramas a/<tema> y b/<tema>; PR a main en cada unión.
- Nunca subas .env ni claves de API.
```

## 5. Fase 0 (juntos, 1 hora): contrato y datos del caso

Esta es la única fase en la que los dos trabajan sobre lo mismo. Se hace en una sola sesión de Claude Code, con los dos frente a la pantalla, y al terminar se sube a `main`. Todo lo que sale de aquí queda congelado: es lo que permite trabajar después sin depender del otro.

```text
FASE 0 (la hacemos juntos). Lee CLAUDE.md y docs/historia.md completos antes de empezar.

1. Crea la estructura del repositorio según CLAUDE.md: game/, server/, tools/, contract/schemas/, contract/fixtures/, content/public/, content/generated/, assets_generated/portraits/, docs/, tests/contract/. Agrega .gitignore (.env, .venv/, *.db, game/.godot/, __pycache__/) y .env.example con las variables vacías.

2. Convierte la historia en datos JSON:
   a. content/public/world.json: lugares del pueblo (plaza, iglesia, campanario, pupusería La Bendición, puesto policial, casa parroquial, caseta de vigilancia, casa de los Portillo, cantina, terminal, mercado, cementerio, quebrada) con id, nombre, acto en que se desbloquea y objetos examinables (id, nombre, descripción visible, id de la evidencia que entrega).
   b. content/public/evidence.json: catálogo de evidencias con id, nombre y descripción visible. Incluye las 6 pruebas de la solución y las pistas falsas (huellas invertidas, cabello negro, marcas de garras, surcos de ruedas, perfume floral, moneda de plata, registro eléctrico del apagón).
   c. content/public/characters.json: los 10 testigos y los 6 sospechosos con id, nombre, rol, lugar, frase de presentación (la cita de la historia) y mvp: true/false.
   d. server/data/case_secret.json: la solución, las 6 pruebas y, por cada testigo: pista verdadera, mentira, evidencia que la contradice, deducción que produce y el texto guía de los 3 niveles (inicial, confrontada, confesion). Usa el interrogatorio de Don Alcides de la sección 5 de la historia como modelo. Define también qué deducciones desbloquean el Acto II y el Acto III.
   e. server/data/endings.json: reglas y textos de los finales. malo = sospechoso equivocado; gris = culpable correcto con decision "negociar" o pruebas incompletas; verdadero = culpable correcto, decision "revelar" y al menos 5 de las 6 pruebas.

3. Escribe el contrato en contract/schemas/ (JSON Schema 2020-12), un archivo por petición y respuesta:
   - WorldState: session_id, act (1-3), clock ("23:47"), evidence [ids], deductions [ids], npcs [{id, level, trust 0-10, fear 0-10, met}], unlocked_locations [ids], can_accuse, ended.
   - TalkRequest {session_id, npc_id, text (máx. 300), want_audio} -> TalkResponse {reply, emotion, level, trust, fear, new_evidence [], new_deductions [], audio_url (o null), source: llm|cache|fallback, state}.
   - PresentRequest {session_id, npc_id, evidence_id, want_audio} -> PresentResponse {reply, emotion, contradiction (bool), level, new_deductions [], audio_url, state}.
   - ExamineRequest {session_id, object_id} -> ExamineResponse {text, new_evidence [], state}.
   - AccuseRequest {session_id, suspect_id, evidence_ids [], decision: revelar|negociar} -> Ending {ending_id: malo|gris|verdadero, title, text, scene}.
   - SttResponse {text}. ApiError {error, detail}.

4. Escribe contract/fixtures/ con un ejemplo válido de cada respuesta, con datos reales del caso pero sin revelar la solución. Incluye al menos: una respuesta de Doña Chonita en nivel inicial, un present a Don Alcides con contradiction=true y uno con false, y un ejemplo de cada final.

5. Escribe tests/contract/test_fixtures.py que valide todas las fixtures contra los schemas (jsonschema + pytest) y córrelo.

6. Antes del commit, muéstrame una tabla: testigo | mentira | evidencia que la contradice | deducción. La revisamos juntos.
```

Al terminar: un commit `chore: fase 0 - contrato y datos del caso` en `main`. Desde aquí, cada uno abre su propio Claude Code con el prompt de su rol.

## 6. Prompt del Ingeniero A: Godot

Se pega una vez en Claude Code, abierto en la raíz del repositorio con el MCP de Godot conectado. Claude Code hace una fase, la prueba y espera "siguiente fase".

```text
Eres el Ingeniero A de Leyendas SV. Lee CLAUDE.md y docs/historia.md antes de empezar. Trabajas SOLO en game/. Tienes el MCP de Godot: úsalo para correr el proyecto y leer la salida de depuración después de cada cambio importante. Godot 4.7.2, GDScript con tipos estáticos, 1280x720, pixel art con filtro Nearest.

REGLA DE INDEPENDENCIA: nunca esperes al motor. Todo pasa por el autoload Backend, que tiene dos modos: "mock" (responde con contract/fixtures/ y simula avances de nivel y evidencias) y "http" (llama a API_BASE_URL). Por defecto, "mock". Los retratos se cargan de assets_generated/portraits/{id}_{emocion}.png y, si no existen, de game/assets/placeholders/. Los nombres y lugares salen de content/public/*.json; si existe content/generated/characters_public.json, lo usas para biografías y edades.

FASE A1 - Esqueleto
- Proyecto en game/ con carpetas scenes/, scripts/, ui/, assets/placeholders/.
- Autoloads: GameState (último WorldState recibido), Backend (mock/http, con señales de respuesta y error), ContentDB (lee content/public/), SceneRouter (cambio de escenas con fundido).
- MockBackend: implementa talk, present, examine, accuse y session con las fixtures; sube de nivel a un testigo cuando recibe la evidencia correcta del ejemplo de Don Alcides.
- Retrato placeholder por personaje: silueta de color con su nombre.
- Escena de título: Nueva partida, Opciones, Salir.
- Prueba: correr con el MCP y cero errores en la salida.

FASE A2 - El pueblo (Acto I)
- Escena Pueblo con TileMapLayer: plaza central y fachadas de iglesia, pupusería La Bendición, puesto policial, casa parroquial, caseta de vigilancia y casa de los Portillo. Arte placeholder, paleta nocturna, faroles.
- Jugador top-down (CharacterBody2D, 4 direcciones) y cámara que lo sigue.
- Los 6 testigos MVP en su lugar según characters.json, con zona de interacción (tecla E).
- Objetos examinables según world.json; al examinar llama Backend.examine y muestra el texto.
- HUD: reloj "11:47 p. m.", acto actual y contador de evidencias.

FASE A3 - Interrogatorio
- Pantalla de diálogo: retrato con emoción, nombre, texto letra a letra, LineEdit para preguntar libremente (Enter envía), indicador de nivel (Declaración / Confrontada / Confesión parcial) y barras de confianza y miedo.
- Botón "Presentar evidencia": selector con las evidencias del jugador; llama Backend.present. Si contradiction es true: sacudida de pantalla, sonido y la deducción nueva en pantalla.
- Animación de espera mientras llega la respuesta; si pasan 15 s, frase de respaldo del personaje.

FASE A4 - Diario, campanario y acusación
- Diario (tecla Tab) con pestañas: Evidencias, Deducciones, Testigos (qué dijo cada uno y en qué nivel está) y Línea de tiempo (11:30, 11:47, 11:54).
- Escena Iglesia y Campanario, que se abre cuando unlocked_locations la incluye.
- Pantalla de acusación (cuando can_accuse es true): elegir 1 de los 6 sospechosos, las evidencias y la decisión revelar o negociar; llama Backend.accuse.
- Escenas de los 3 finales (malo, gris, verdadero) con texto y fondo.

FASE A5 - Voz y pulido
- Reproducir audio_url (MP3 con AudioStreamMP3) cuando llegue en la respuesta.
- Push-to-talk (tecla V): grabar con AudioStreamMicrophone y AudioEffectRecord, guardar WAV, enviarlo a /stt y poner el texto en el LineEdit para que el jugador lo confirme.
- Ambiente: campanada a las 11:47, viento, música baja.
- Opciones: API_BASE_URL editable y switch mock/http.
- Exportar el build de Windows.

Al terminar cada fase: corre el proyecto con el MCP, confirma cero errores, dame el comando para probar, propone el mensaje de commit y espera "siguiente fase".
```

## 7. Prompt del Ingeniero B: motor de IA, personajes y voz

Se pega una vez en Claude Code, abierto en la raíz del repositorio en la PC con la RTX. No necesita el MCP de Godot.

```text
Eres el Ingeniero B de Leyendas SV. Lee CLAUDE.md y docs/historia.md antes de empezar. Trabajas SOLO en server/, tools/, content/generated/ y assets_generated/. Python 3.12, FastAPI, Windows 11, PC con RTX serie 50 de 12 GB de VRAM y 32 GB de RAM.

REGLA DE INDEPENDENCIA: nunca esperes al cliente Godot. Prueba todo con pytest y llamadas HTTP. Toda respuesta del motor debe validar contra contract/schemas/. El modelo de lenguaje solo redacta lo que dice el personaje; las reglas del juego (niveles, evidencias, finales) las decide el código.

FASE B1 - Motor base y modelo
- server/app/main.py con FastAPI; escucha en 0.0.0.0:8000 para que Godot entre por la red local.
- Configuración por .env: LLM_PROVIDER (ollama|nvidia), LLM_MODEL, NVIDIA_API_KEY, STT_PROVIDER, STT_API_KEY, TTS_PROVIDER.
- server/app/llm/provider.py: chat(messages, schema) con Ollama nativo (nemotron-3-nano:4b, think=false, format=schema, keep_alive=-1) y cliente compatible con OpenAI para la API de NVIDIA. Llamada de calentamiento al arrancar.
- GET /health, POST /session y GET /session/{id}, con estado en SQLite.
- tools/smoke_llm.py: 10 preguntas a Doña Chonita; mide latencia (meta: menos de 3 s) y revisa la calidad del español.

FASE B2 - Personajes desde Nemotron-Personas-El-Salvador
- server/pipelines/personas.py: carga nvidia/Nemotron-Personas-El-Salvador con la librería datasets en modo streaming. Imprime primero el esquema real de columnas y un registro de ejemplo; no supongas nombres de campos.
- Para cada testigo, filtra personas compatibles con su arquetipo (sexo, rango de edad, ocupación, zona rural o urbana) y elige la mejor. Ejemplos: Doña Chonita, mujer de 50 a 65 años en comercio de alimentos; Don Chepe, hombre de 40 a 60 en transporte; Agente Ramírez, hombre de 30 a 45 en seguridad pública.
- Con el LLM, fusiona persona + rol de la historia en server/data/characters/{id}.json: biografía corta, forma de hablar con modismos salvadoreños, muletillas, familia, miedos, voz de Magpie asignada y visual_prompt para el retrato. La persona aporta realismo; la historia manda sobre el rol, la pista y la mentira.
- Exporta la parte pública (nombre, edad, oficio, biografía corta) a content/generated/characters_public.json.
- Guarda el uuid de cada persona usada y la atribución CC BY 4.0 del dataset en server/CREDITS.md.
- Extra si sobra tiempo: 10 a 20 vecinos de fondo con una frase ambiental cada uno.

FASE B3 - Interrogatorio
- POST /talk: arma el prompt con la ficha del personaje, su nivel actual, la pista que puede contar en ese nivel, la mentira que debe sostener, la memoria (últimos 6 turnos y un resumen) y su confianza y miedo. El modelo responde JSON {reply, emotion, trust_delta, fear_delta}, máximo 3 frases. Nunca revela la solución ni pistas de un nivel superior.
- POST /present: determinista. Si la evidencia contradice a ese testigo según case_secret.json, sube de nivel, agrega la deducción y devuelve contradiction=true; el modelo solo redacta la reacción. Si no, el modelo genera una respuesta evasiva en personaje.
- POST /examine: entrega evidencias según world.json y el acto actual.
- Avance de actos: desbloquea lugares cuando se reúnen las deducciones definidas en case_secret.json.
- POST /accuse con las reglas de endings.json.
- Filtros de entrada y salida, caché de respuestas y modo demo (DEMO_MODE=1: partida guardada con 2 evidencias ya encontradas).

FASE B4 - Voz
- POST /stt: recibe WAV y lo transcribe con nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B por API alojada compatible con OpenAI, en español. Respaldo: faster-whisper small en CPU.
- Cuando want_audio es true, genera MP3 con Magpie TTS Multilingual (API de NVIDIA, voz en español según la ficha y la emoción más cercana disponible), lo cachea y devuelve audio_url hacia GET /audio/{id}.mp3. Respaldo: Piper es_MX local.
- Mide y reporta la latencia total de texto más audio.

FASE B5 - Retratos
- server/pipelines/portraits.py: desde el visual_prompt de cada ficha, genera con ComfyUI (SDXL, API local) retratos de 512x512 en pixel art de 16 bits, uno por emoción, en assets_generated/portraits/{id}_{emocion}.png. Misma base de estilo y semilla para todos. Haz lo mismo con los 6 sospechosos.
- Nunca corras ComfyUI mientras Ollama responde en vivo: comparten los 12 GB de VRAM.

Al terminar cada fase: pytest pasa, las respuestas validan contra contract/schemas, dame el comando para probar, propone el mensaje de commit y espera "siguiente fase".
```

## 8. Uniones y checklist de demo

Cada unión la conduce el Ingeniero A en su Claude Code, con el motor del Ingeniero B corriendo en la red local. Se repite el mismo prompt en las tres uniones; solo cambia qué se espera que funcione.

```text
UNIÓN (las ramas de A y B ya están unidas en main y el motor está corriendo en la PC con RTX).
1. Haz git pull de main.
2. Corre tests/contract/ y confirma que el motor real responde igual que las fixtures.
3. En Godot, cambia Backend a modo http con API_BASE_URL=http://<IP de la PC con RTX>:8000 y verifica /health.
4. Juega con el MCP lo que corresponde a esta unión y reporta cada error o diferencia entre fixtures y respuestas reales.
5. Si el problema está en game/, arréglalo. Si está en el motor, descríbelo con la petición y la respuesta exactas para el Ingeniero B, sin tocar server/.
6. Confirma que los retratos reales reemplazan a los placeholders cuando existen.
```

| Unión | Cuándo | Qué tiene que funcionar |
| --- | --- | --- |
| Unión 1 | Cierre del día 1 | Hablar con Doña Chonita en vivo y quebrar a Don Alcides presentando la evidencia correcta |
| Unión 2 (v0.9) | Mediodía del día 2 | Partida completa: 6 testigos, campanario, acusación y los 3 finales |
| Unión final (v1.0) | 1 hora antes de presentar | Retratos y voces reales, modo demo listo; después solo errores críticos |

**Checklist de demo:**

- [ ] Llevar el router MikroTik y armar una red propia, para no depender del Wi-Fi del evento
- [ ] Reservar una IP fija para la PC con RTX y ponerla en las Opciones del juego
- [ ] Abrir el puerto 8000 en el firewall de Windows solo para la red privada
- [ ] Arrancar Ollama, el motor y verificar /health antes de subir al escenario
- [ ] Probar el modo demo y tener a mano el modo mock por si el motor falla
- [ ] Grabar un video de respaldo de la partida completa
- [ ] Ensayar que un juez intente romper a un testigo con preguntas fuera de lugar
- [ ] En el pitch, mencionar los tres modelos de NVIDIA y el dataset salvadoreño con su licencia CC BY 4.0
