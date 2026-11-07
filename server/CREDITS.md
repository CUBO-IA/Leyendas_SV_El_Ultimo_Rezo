# Créditos de datos

## Nemotron-Personas-El-Salvador

Las fichas de los testigos (`server/data/characters/`, `content/generated/characters_public.json`)
se basan en personas sintéticas del dataset **Nemotron-Personas-El-Salvador** de NVIDIA,
publicado bajo licencia [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/):
https://huggingface.co/datasets/nvidia/Nemotron-Personas-El-Salvador

**Cambios:** cada persona se fusionó con un personaje ficticio del juego mediante un modelo de
lenguaje (nombre, oficio y lugar los define la historia; se trasladó a un pueblo ficticio).
Generado con `server/pipelines/personas.py`.

| Testigo | Nombre en el juego | uuid de la persona |
| --- | --- | --- |
| chonita | María Asunción Gómez Mendoza | `05dcb619-983d-433a-90bd-257e22b97083` |
| chepe | José Martínez Hernández | `77b3ed3a-66ce-47f2-bc79-03dbf1c7fe6b` |
| chente | Vicente Martínez González | `0eedf840-9996-4582-b62e-90abab01d4c5` |
| ramirez | Agustín Ramírez | `046e0b95-b5c7-4a34-a6f7-bad308fee147` |
| padre_mauricio | Mauricio Hernández Méndez | `39489295-a0b0-40cc-9952-f7e033747fd7` |
| tonito | Antonio Gómez Martínez | `87c8f563-74ff-408f-bf3c-1bc7ada429b9` |
| beto | Roberto Pérez Rodríguez | `71dd4370-0cfe-4472-a5a9-22c732f35f53` |
| pilo | Emerson Antonio García | `bca556f0-77b5-4b55-be9f-91639fefc723` |
| alcides | Alcides Martínez García | `80afc9f2-ae4b-4a0b-9948-8d175be0d343` |
| mercedes | María Mercedes Portillo de Cruz | `1e94d392-5890-486e-a28a-38d87ab7c45c` |
