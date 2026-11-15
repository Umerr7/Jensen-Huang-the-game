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


static func go_to(tree: SceneTree, id: String, last_line: String = "") -> void:
	ending_id = id
	final_line = last_line
	tree.change_scene_to_file.call_deferred(SCENES.get(id, SCENES[REVENGE]))
