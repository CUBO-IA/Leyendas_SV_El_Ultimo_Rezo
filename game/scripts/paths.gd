class_name Paths
extends RefCounted
## Rutas a los datos que viven FUERA de game/: content/, contract/fixtures/ y
## assets_generated/. Se leen del disco para tener una sola fuente de verdad.
## En el editor, la raíz del repo es res://..; en un build exportado se busca
## junto al ejecutable.

static var _root: String = ""


static func repo_root() -> String:
	if _root != "":
		return _root
	var candidates: Array[String] = []
	var res_dir: String = ProjectSettings.globalize_path("res://")
	if res_dir != "":
		candidates.append(res_dir.path_join(".."))
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	candidates.append(exe_dir)
	candidates.append(exe_dir.path_join(".."))
	for c: String in candidates:
		var p: String = c.simplify_path()
		if DirAccess.dir_exists_absolute(p.path_join("contract/fixtures")):
			_root = p
			return _root
	push_error("No encuentro la raíz del repo (contract/fixtures). Probé: %s" % [candidates])
	_root = candidates[0].simplify_path()
	return _root


static func content(rel: String) -> String:
	return repo_root().path_join("content").path_join(rel)


static func fixture(fixture_name: String) -> String:
	return repo_root().path_join("contract/fixtures/%s.json" % fixture_name)


static func portrait(id: String, emotion: String) -> String:
	return repo_root().path_join("assets_generated/portraits/%s_%s.png" % [id, emotion])


## Lee un JSON del disco. Devuelve null si no existe o no se puede parsear.
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("JSON inválido: %s" % path)
	return parsed
