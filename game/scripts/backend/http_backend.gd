class_name HttpBackend
extends Node
## Cliente HTTP + JSON del motor. Cada petición usa su propio HTTPRequest,
## así varias pueden ir en paralelo. Los errores del motor llegan como ApiError
## {error, detail}; los de red se traducen a {error: "network"|"timeout", detail}.


func request_json(method: int, url: String, body: Variant, timeout: float) -> Dictionary:
	var payload: String = "" if body == null else JSON.stringify(body)
	var headers: PackedStringArray = ["Accept: application/json"]
	if body != null:
		headers.append("Content-Type: application/json")
	return await _send(method, url, headers, payload.to_utf8_buffer(), timeout)


func request_raw(url: String, data: PackedByteArray, content_type: String, timeout: float) -> Dictionary:
	var headers: PackedStringArray = ["Accept: application/json", "Content-Type: " + content_type]
	return await _send(HTTPClient.METHOD_POST, url, headers, data, timeout)


func _send(method: int, url: String, headers: PackedStringArray, data: PackedByteArray,
		timeout: float) -> Dictionary:
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	var err: Error = req.request_raw(url, headers, method, data)
	if err != OK:
		req.queue_free()
		return _fail("network", "No se pudo enviar la petición a %s (%s)." % [url, error_string(err)])
	var out: Array = await req.request_completed
	req.queue_free()

	var result: int = out[0]
	var code: int = out[1]
	var raw: PackedByteArray = out[3]
	if result == HTTPRequest.RESULT_TIMEOUT:
		return _fail("timeout", "El motor tardó más de %d s en responder." % int(timeout))
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("network", "No hay conexión con el motor en %s (código %d)." % [url, result])

	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if code >= 200 and code < 300 and parsed is Dictionary:
		return {"ok": true, "data": parsed, "error": {}, "status": code}
	if parsed is Dictionary and (parsed as Dictionary).has("error"):
		return {"ok": false, "data": {}, "error": parsed, "status": code}
	return _fail("internal", "Respuesta inesperada del motor (HTTP %d)." % code, code)


static func _fail(error: String, detail: String, status: int = 0) -> Dictionary:
	return {"ok": false, "data": {}, "error": {"error": error, "detail": detail}, "status": status}
