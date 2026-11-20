# Carries the result of Alice's conversation into the ending scene.
# (Static vars survive change_scene_to_file, so no autoload is needed.)
class_name GameEnding
extends RefCounted

const RECONCILIATION := "reconciliation"   # Ending 1 - The Unexpected Comeback
const SACRIFICE := "sacrifice"             # Ending 2 - The Final Sacrifice
const BETRAYAL := "betrayal"               # Ending 3 - The Honeypot
const REVENGE := "revenge"                 # Ending 4 - Revenge Without Answers (no AI)

const AI_ENDINGS := [RECONCILIATION, SACRIFICE, BETRAYAL]

## Which scene each ending switches to.
const SCENES := {
	RECONCILIATION: "res://endings/ending_reconciliation.tscn",
	SACRIFICE: "res://endings/ending_sacrifice.tscn",
	BETRAYAL: "res://endings/ending_betrayal.tscn",
	REVENGE: "res://endings/ending_revenge.tscn",
}

## The ending that was reached and Alice's last line (empty for revenge).
static var ending_id : String = ""
static var final_line : String = ""
## The whole conversation, as [{"who": "Jensen"/"Alice", "text": ...}].
static var transcript : Array = []


## Every ending the player has ever reached is saved here (in a browser this
## lives in the browser's storage, so it survives closing the tab).
const SAVE_PATH := "user://endings_reached.cfg"


static func go_to(tree: SceneTree, id: String, last_line: String = "") -> void:
	ending_id = id
	final_line = last_line
	_record(id)
	tree.change_scene_to_file.call_deferred(SCENES.get(id, SCENES[REVENGE]))


static func _record(id: String) -> void:
	if not SCENES.has(id):
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)                # fine if it doesn't exist yet
	cfg.set_value("reached", id, true)
	cfg.set_value("stats", "playthroughs", int(cfg.get_value("stats", "playthroughs", 0)) + 1)
	cfg.save(SAVE_PATH)


## How many times the player has reached any ending (repeats included).
static func playthroughs() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0
	return int(cfg.get_value("stats", "playthroughs", 0))


## How many different endings this player has reached so far.
static func reached_count() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("reached"):
		return 0
	var count := 0
	for key in cfg.get_section_keys("reached"):
		if SCENES.has(key):
			count += 1
	return count
