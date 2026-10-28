class_name IKItemDatabase
extends Resource
## Registry of item definitions, looked up by their stable id.

@export var items: Array[IKItemDefinition] = []:
	set(value):
		items = value
		_index_dirty = true

var _index: Dictionary = {}
var _index_dirty := true
var _indexed_count := -1


func get_item(item_id: StringName) -> IKItemDefinition:
	_ensure_index()
	return _index.get(item_id)


func has_item(item_id: StringName) -> bool:
	_ensure_index()
	return _index.has(item_id)


func add_item(definition: IKItemDefinition) -> void:
	items.append(definition)
	_index_dirty = true


## Call after replacing or editing definitions inside [member items] in place.
func refresh() -> void:
	_index_dirty = true


func get_ids() -> Array[StringName]:
	_ensure_index()
	var ids: Array[StringName] = []
	ids.assign(_index.keys())
	return ids


## Returns human-readable problems: null entries, empty or duplicate ids, bad stack sizes.
func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	var seen := {}
	for i in items.size():
		var definition := items[i]
		if definition == null:
			issues.append("Entry %d is empty." % i)
			continue
		if definition.id == &"":
			issues.append("Entry %d (%s) has no id." % [i, definition.resource_path])
			continue
		if seen.has(definition.id):
			issues.append("Duplicate id '%s' (entries %d and %d)." % [definition.id, seen[definition.id], i])
		else:
			seen[definition.id] = i
		if definition.max_stack < 1:
			issues.append("Item '%s' has max_stack < 1." % definition.id)
		if definition.unique and definition.max_stack > 1:
			issues.append("Item '%s' is unique: max_stack %d is ignored." % [definition.id, definition.max_stack])
	return issues


func _ensure_index() -> void:
	if not _index_dirty and _indexed_count == items.size():
		return
	_index.clear()
	for definition in items:
		# First definition wins on duplicates; validate() reports them.
		if definition != null and definition.id != &"" and not _index.has(definition.id):
			_index[definition.id] = definition
	_index_dirty = false
	_indexed_count = items.size()
