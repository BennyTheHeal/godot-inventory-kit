class_name IKLoadReport
extends RefCounted
## What happened during a load. Check [member ok] first, then [member overflow].
##
## When [member ok] is false, no container was changed.

var ok := false
var error := ""
## Format version found in the document, before migrations.
var source_version := 0
## Where the data came from when loaded through [IKSaveFile]: "main", "tmp" or "backup".
var source := ""
## Problems that were repaired automatically (relocated stacks, regenerated uids...).
var warnings := PackedStringArray()
## Stacks that could not be placed back: [code]{"container_id": StringName, "stack": IKItemStack}[/code].
## Nothing is destroyed silently: give these to the player (drop on the ground, mailbox...).
var overflow: Array[Dictionary] = []
## Stacks kept whose item is missing from the database.
var unknown_items := 0
## Entries that were unreadable (or unknown items, if keep_unknown_items is false).
var dropped := 0
## Saved containers that were not passed to the load, by id (raw data, kept for re-saving).
var unmatched_containers: Dictionary = {}


func fail(message: String) -> IKLoadReport:
	ok = false
	error = message
	return self


func warn(message: String) -> void:
	warnings.append(message)


func _to_string() -> String:
	if not ok:
		return "IKLoadReport(failed: %s)" % error
	return "IKLoadReport(ok, v%d, %d warnings, %d overflow, %d unknown, %d dropped)" % [
		source_version, warnings.size(), overflow.size(), unknown_items, dropped]
