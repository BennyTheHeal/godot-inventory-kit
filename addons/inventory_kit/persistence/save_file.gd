class_name IKSaveFile
extends RefCounted
## Crash-safe save file for containers.
##
## Writing: the document goes to "<path>.tmp", is read back and verified, the
## previous valid save is kept as "<path>.bak", then the temp file replaces the
## main one. Each file starts with a header line holding a SHA-256 checksum.
##
## Loading tries the main file, then the temp file (a save interrupted right
## before its last step), then the backup. A file whose checksum is valid is
## never skipped: if its content is refused (e.g. written by a newer build),
## loading fails instead of silently falling back to older data.
## [codeblock]
## var save := IKSaveFile.new("user://slot1/inventory.json")
## save.save([bag, equipment, chest])
## var report := save.load_into([bag, equipment, chest])
## [/codeblock]

const HEADER_FORMAT := "inventory_kit_save"

var path: String
## Containers found in the last loaded save that were not passed to load_into().
## They are written back on save(), so data for containers not loaded yet is kept.
var _unmatched: Dictionary = {}


func _init(p_path: String = "user://inventory.json") -> void:
	path = p_path


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp") \
		or FileAccess.file_exists(path + ".bak")


func save(containers: Array) -> Error:
	var doc := IKSerializer.to_dict(containers)
	for container_id in _unmatched:
		if not doc.containers.has(String(container_id)):
			doc.containers[String(container_id)] = _unmatched[container_id]
	return write_document(path, doc)


func load_into(containers: Array, options: IKLoadOptions = null) -> IKLoadReport:
	var problems := PackedStringArray()
	for candidate in [[path, "main"], [path + ".tmp", "tmp"], [path + ".bak", "backup"]]:
		var file_path: String = candidate[0]
		if not FileAccess.file_exists(file_path):
			continue
		var read := read_document(file_path)
		if not read.ok:
			problems.append("%s: %s" % [file_path.get_file(), read.error])
			continue
		var report := IKSerializer.load_into(read.doc, containers, options)
		report.source = candidate[1]
		if report.ok:
			_unmatched = report.unmatched_containers
			for problem in problems:
				report.warn("Skipped damaged %s" % problem)
		return report
	var failed := IKLoadReport.new()
	if problems.is_empty():
		return failed.fail("No save file at %s." % path)
	return failed.fail("Every save file is damaged: %s" % "; ".join(problems))


## Writes [param doc] atomically. Returns OK or the first file error.
static func write_document(file_path: String, doc: Dictionary) -> Error:
	var payload := JSON.stringify(doc, "\t")
	var header := JSON.stringify({"format": HEADER_FORMAT, "sha256": payload.sha256_text()})
	var directory := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return made
	var temp_path := file_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(header + "\n" + payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	if not read_document(temp_path).ok:
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(file_path):
		# Only a valid save may become the backup; a damaged one is set aside.
		var keep_as := ".bak" if read_document(file_path).ok else ".corrupt"
		var moved := _replace(file_path, file_path + keep_as)
		if moved != OK:
			return moved
	return _replace(temp_path, file_path)


## {"ok": bool, "doc": Dictionary, "error": String}
static func read_document(file_path: String) -> Dictionary:
	var result := {"ok": false, "doc": {}, "error": ""}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result.error = "cannot open (%s)" % error_string(FileAccess.get_open_error())
		return result
	var text := file.get_as_text()
	file.close()
	var newline := text.find("\n")
	if newline < 0:
		result.error = "missing header"
		return result
	var json := JSON.new()
	if json.parse(text.substr(0, newline)) != OK or not json.data is Dictionary \
			or json.data.get("format") != HEADER_FORMAT:
		result.error = "invalid header"
		return result
	var payload := text.substr(newline + 1)
	if payload.sha256_text() != json.data.get("sha256"):
		result.error = "checksum mismatch (truncated or edited)"
		return result
	if json.parse(payload) != OK or not json.data is Dictionary:
		result.error = "invalid JSON"
		return result
	result.ok = true
	result.doc = json.data
	return result


static func _replace(from: String, to: String) -> Error:
	if FileAccess.file_exists(to):
		var removed := DirAccess.remove_absolute(to)
		if removed != OK:
			return removed
	return DirAccess.rename_absolute(from, to)
