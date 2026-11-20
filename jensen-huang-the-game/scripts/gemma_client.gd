# Talks to Google's Gemini API over HTTPS (Gemini Flash-Lite by default; Gemma works too).
#
#   var reply := await gemma.ask(system_text, contents)
#   if reply.ok: print(reply.text)
#
# `contents` is the chat history in Gemini format:
#   [{"role": "user", "parts": [{"text": "..."}]}, {"role": "model", "parts": [...]}, ...]
#
# Two ways to reach Google:
#   * proxy_url set (the normal way): requests go to our Cloudflare Worker
#     (cloudflare-worker/worker.js), which adds the key. The game ships NO key.
#   * proxy_url empty: the game calls Google directly with its own key,
#     read (first one found wins) from:
#   1. the GEMMA_API_KEY environment variable
#   2. res://secrets/gemma_api_key.txt   (git-ignored, never commit it)
#   3. user://gemma_api_key.txt
class_name GemmaClient
extends Node

const ENDPOINT := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

## Our Cloudflare Worker, e.g. "https://haven-alice.yourname.workers.dev".
## When set, no API key is needed (or shipped) at all.
@export var proxy_url : String = ""

## Main model. Gemini 3.5 Flash-Lite answers in ~2 s (Gemma 4 took 10-30 s).
## To go back to Gemma: model "gemma-4-26b-a4b-it", fallback "gemma-4-31b-it",
## thinking_level "" and json_mode off (Gemma supports neither).
@export var model : String = "gemini-3.5-flash-lite"
## Optional second model raced alongside the main one; whichever answers first
## wins. Empty = off. (It doubles API usage, and "gemini-flash-lite-latest" is
## just another name for gemini-3.5-flash-lite, so racing those gained nothing.)
@export var fallback_model : String = ""
## "minimal" = (almost) no hidden reasoning = fastest. Empty = model default.
@export var thinking_level : String = "minimal"
## Ask the API to return pure JSON (Gemini models only).
@export var json_mode : bool = true
## One request's time limit. Replies normally take 1.5-3.5 s; a request that
## hangs much longer than that is retried instead of making the player wait.
@export var timeout_seconds : float = 10.0
## Most time one ask() may take, retries included. After that Alice uses an
## offline line so the player is never stuck waiting.
@export var total_budget_seconds : float = 25.0
## How many times each racing model may retry after an error.
@export var max_attempts_per_model : int = 3
@export var temperature : float = 0.9
## Thinking eats into this budget too, so keep it generous.
@export var max_output_tokens : int = 1024

## Sent when running outside a browser, so a website-restricted key still works in the editor.
@export var editor_referer : String = "https://html-classic.itch.zone/"

var _api_key : String = ""


func _ready() -> void:
	if proxy_url != "":
		return                   # the Worker holds the key
	_api_key = load_api_key()
	if _api_key == "":
		push_warning("GemmaClient: no API key found (see top of gemma_client.gd). Alice will use offline lines.")


static func load_api_key() -> String:
	var env := OS.get_environment("GEMMA_API_KEY").strip_edges()
	if env != "":
		return env
	for path in ["res://secrets/gemma_api_key.txt", "user://gemma_api_key.txt"]:
		if FileAccess.file_exists(path):
			var key := FileAccess.get_file_as_string(path).strip_edges()
			if key != "":
				return key
	return ""


func has_key() -> bool:
	return proxy_url != "" or _api_key != ""


## Asks Gemma and returns the FIRST good answer.
## Speed trick: both models are asked at the same time and race each other.
## Google's Gemma endpoints often fail instantly with 500/503; a failed racer
## immediately tries again, so a hiccup doesn't cost a whole round trip.
## Returns {"ok": bool, "text": String, "error": String}.
func ask(system_text: String, contents: Array) -> Dictionary:
	if not has_key():
		return {"ok": false, "text": "", "error": "no API key"}
	var race := {"done": false, "result": {}, "racing": 0, "errors": [],
		"deadline": Time.get_ticks_msec() / 1000.0 + total_budget_seconds}
	for m in [model, fallback_model]:
		if m != "":
			_racer(m, system_text, contents, race)   # not awaited: they run side by side
	while not race.done and race.racing > 0 and Time.get_ticks_msec() / 1000.0 < race.deadline:
		await get_tree().process_frame
	if race.done:
		return race.result
	return {"ok": false, "text": "", "error": "; ".join(race.errors) if not race.errors.is_empty() else "out of time"}


func _racer(model_name: String, system_text: String, contents: Array, race: Dictionary) -> void:
	race.racing += 1
	for attempt in max_attempts_per_model:
		var remaining : float = race.deadline - Time.get_ticks_msec() / 1000.0
		if race.done or remaining < 5.0:
			break
		var result := await _request(model_name, system_text, contents, minf(timeout_seconds, remaining))
		if race.done:
			break                      # the other model already won
		if result.ok:
			race.done = true
			race.result = result
			break
		race.errors.append("%s: %s" % [model_name, result.error.left(60)])
		push_warning("GemmaClient: %s attempt %d failed (%s)" % [model_name, attempt + 1, result.error.left(60)])
		if result.error.begins_with("HTTP 4") and not result.error.begins_with("HTTP 429"):
			break                      # bad key / bad request: retrying won't help
		# Instant 500s: retry almost straight away. 429 = too many requests: back off.
		var wait := 4.0 if result.error.begins_with("HTTP 429") else 0.5 + attempt * 0.75
		await get_tree().create_timer(wait).timeout
	race.racing -= 1


func _request(model_name: String, system_text: String, contents: Array, timeout: float) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	# In a browser the reply arrives already decompressed; letting Godot try to
	# gunzip it again fails with "network result 8" (this broke Alice on itch.io).
	http.accept_gzip = not OS.has_feature("web")
	add_child(http)
	var body := {
		"systemInstruction": {"parts": [{"text": system_text}]},
		"contents": contents,
		"generationConfig": {"temperature": temperature, "maxOutputTokens": max_output_tokens},
	}
	if json_mode:
		body.generationConfig["responseMimeType"] = "application/json"
	if thinking_level != "":
		body.generationConfig["thinkingConfig"] = {"thinkingLevel": thinking_level}
	var url := ENDPOINT % model_name
	var headers := ["Content-Type: application/json"]
	if proxy_url != "":
		url = proxy_url
		body["model"] = model_name       # the Worker picks the Google model from this
	else:
		headers.append("x-goog-api-key: " + _api_key)
	if proxy_url == "" and not OS.has_feature("web"):
		# The shipped key only accepts requests from itch.io. Browsers send that
		# automatically; editor/desktop runs don't, so say it here for local testing.
		headers.append("Referer: " + editor_referer)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "text": "", "error": "request() error %d" % err}

	var response : Array = await http.request_completed   # [result, code, headers, body]
	http.queue_free()
	var code : int = response[1]
	var text : String = (response[3] as PackedByteArray).get_string_from_utf8()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "text": "", "error": "network result %d" % response[0]}
	if code != 200:
		return {"ok": false, "text": "", "error": "HTTP %d: %s" % [code, text.left(200)]}

	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("candidates") or data.candidates.is_empty():
		return {"ok": false, "text": "", "error": "unexpected response: " + text.left(200)}
	# Gemma 4 returns its hidden reasoning as parts marked "thought": skip those.
	var answer := ""
	for part in data.candidates[0].get("content", {}).get("parts", []):
		if not part.get("thought", false):
			answer += part.get("text", "")
	if answer.strip_edges() == "":
		return {"ok": false, "text": "", "error": "empty answer (finishReason %s)" % data.candidates[0].get("finishReason", "?")}
	return {"ok": true, "text": answer, "error": ""}


## Pulls the first {...} JSON object out of a reply (models sometimes wrap it
## in ```json fences or add a stray sentence). Returns {} if there isn't one.
static func extract_json(text: String) -> Dictionary:
	var start := text.find("{")
	var end := text.rfind("}")
	if start == -1 or end <= start:
		return {}
	var parsed = JSON.parse_string(text.substr(start, end - start + 1))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
