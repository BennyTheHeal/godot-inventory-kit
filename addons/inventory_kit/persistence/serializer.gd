class_name IKSerializer
extends RefCounted
## Converts containers to plain, versioned Dictionaries and back.
##
## The Dictionary is JSON-safe: embed it in your own save system, or use
## [IKSaveFile] for an atomic file with backups. Loading is all-or-nothing for
## structural errors and self-repairing for item-level problems, which are
## listed in the returned [IKLoadReport]. Items are never destroyed silently:
## what cannot be placed back ends up in [member IKLoadReport.overflow].

const FORMAT := "inventory_kit"


static func to_dict(containers: Array) -> Dictionary:
	var saved := {}
	for container: IKContainer in containers:
		var key := String(container.container_id)
		if key.is_empty() or saved.has(key):
			push_error("IKSerializer: container ids must be unique and non-empty ('%s')." % key)
			continue
		saved[key] = container_to_dict(container)
	return {"format": FORMAT, "version": IKMigrations.CURRENT_VERSION, "containers": saved}


static func container_to_dict(container: IKContainer) -> Dictionary:
	var slots := []
	for i in container.size():
		var stack: IKItemStack = container._slots[i]
		if stack == null:
			continue
		var entry := {"i": i, "id": String(stack.item_id), "n": stack.amount}
		if stack.has_uid():
			entry["uid"] = stack.uid
		if stack.rotated:
			entry["rot"] = true  # grid containers: turned a quarter turn
		if not stack.data.is_empty():
			# Type-tagged so ints stay ints after a JSON round trip.
			entry["data"] = JSON.from_native(stack.data)
		slots.append(entry)
	return {"size": container.size(), "slots": slots}


## Replaces the content of [param containers] with the saved state.
## Containers missing from the document are left untouched (with a warning).
## Emits [signal IKContainer.slots_changed] and [signal IKContainer.changed],
## but not item_added / item_removed: loading is not gameplay.
static func load_into(doc: Dictionary, containers: Array, options: IKLoadOptions = null) -> IKLoadReport:
	var report := IKLoadReport.new()
	if options == null:
		options = IKLoadOptions.new()
	if doc.get("format") != FORMAT:
		return report.fail("Not an Inventory Kit document.")
	var migrations := options.migrations if options.migrations != null else IKMigrations.default()
	var current := migrations.migrate(doc, report)
	if not report.error.is_empty():
		return report
	var saved: Variant = current.get("containers")
	if not saved is Dictionary:
		return report.fail("Missing 'containers' section.")

	var targets := {}
	for container: IKContainer in containers:
		if container == null or container.container_id == &"":
			return report.fail("Every container needs a non-empty container_id.")
		var key := String(container.container_id)
		if targets.has(key):
			return report.fail("Container id '%s' is used twice." % key)
		targets[key] = container
	for key in saved:
		var entry: Variant = saved[key]
		if not entry is Dictionary or not entry.get("slots") is Array:
			return report.fail("Container '%s' is malformed." % key)
		if not targets.has(String(key)):
			report.unmatched_containers[StringName(key)] = (entry as Dictionary).duplicate(true)

	var seen_uids := {}
	var rebuilt := {}
	for key in targets:
		if not saved.has(key):
			report.warn("Container '%s' is not in the save; left unchanged." % key)
			continue
		rebuilt[key] = _rebuild(targets[key], saved[key]["slots"], options, report, seen_uids)

	var changes := {}
	for key in rebuilt:
		var container: IKContainer = targets[key]
		var after: Array = rebuilt[key]
		var changed := PackedInt32Array()
		for i in after.size():
			if not IKItemStack.same(container._slots[i], after[i]):
				changed.append(i)
		container._apply_slots(after)
		changes[key] = changed
	for key in changes:
		var changed: PackedInt32Array = changes[key]
		if not changed.is_empty():
			targets[key].slots_changed.emit(changed)
			targets[key].changed.emit()
	report.ok = true
	return report


static func _rebuild(container: IKContainer, entries: Array, options: IKLoadOptions,
		report: IKLoadReport, seen_uids: Dictionary) -> Array:
	var label := String(container.container_id)
	var slots := []
	slots.resize(container.size())
	var displaced: Array[IKItemStack] = []
	# Grid containers: cells already taken by the stacks placed so far.
	var occupancy := PackedInt32Array()
	if container.is_grid():
		occupancy.resize(slots.size())
		occupancy.fill(-1)
	for entry in entries:
		var read := _read_entry(entry, label, options, report, seen_uids)
		if read.is_empty():
			continue
		var stack: IKItemStack = read[0]
		var index: int = read[1]
		var definition := container.database.get_item(stack.item_id) if container.database else null
		if definition == null:
			if not options.keep_unknown_items:
				report.dropped += 1
				report.warn("%s: unknown item '%s' x%d dropped." % [label, stack.item_id, stack.amount])
				continue
			report.unknown_items += 1
			if index >= 0 and index < slots.size() and slots[index] == null and container._slot_rules[index] == null \
					and _cells_free(container, occupancy, index, stack):
				_put(container, slots, occupancy, index, stack)
			else:
				displaced.append(stack)
			continue
		if not definition.can_rotate:
			stack.rotated = false
		var pieces := _split_to_limits(stack, definition, label, report, seen_uids)
		var first: IKItemStack = pieces[0]
		if index >= 0 and index < slots.size() and slots[index] == null and container._accepts(index, first, definition) \
				and _cells_free(container, occupancy, index, first):
			_put(container, slots, occupancy, index, first)
		else:
			if index < 0 or index >= slots.size():
				report.warn("%s: slot %d no longer exists; '%s' relocated." % [label, index, first.item_id])
			elif slots[index] != null:
				report.warn("%s: slot %d listed twice; '%s' relocated." % [label, index, first.item_id])
			elif container.is_grid() and container._accepts(index, first, definition):
				report.warn("%s: '%s' no longer fits at cell %d; relocated." % [label, first.item_id, index])
			else:
				report.warn("%s: slot %d no longer accepts '%s'; relocated." % [label, index, first.item_id])
			displaced.append(first)
		for i in range(1, pieces.size()):
			displaced.append(pieces[i])
	for stack in displaced:
		_relocate(container, slots, stack, report, occupancy)
	return slots


## Grid containers: true if the cells [param stack] needs at [param index] are inside
## the grid and free. Always true for classic slots.
static func _cells_free(container: IKContainer, occupancy: PackedInt32Array, index: int, stack: IKItemStack) -> bool:
	if not container.is_grid():
		return true
	return container._area_free(occupancy, index, container._size_of(stack))


static func _put(container: IKContainer, slots: Array, occupancy: PackedInt32Array, index: int, stack: IKItemStack) -> void:
	slots[index] = stack
	if container.is_grid():
		container._mark_area(occupancy, index, container._size_of(stack))


## [stack, slot index], or [] if the entry is unreadable.
static func _read_entry(entry: Variant, label: String, options: IKLoadOptions,
		report: IKLoadReport, seen_uids: Dictionary) -> Array:
	if not entry is Dictionary:
		return _drop(report, "%s: unreadable slot entry." % label)
	var raw_id: Variant = entry.get("id")
	if not (raw_id is String or raw_id is StringName) or String(raw_id).is_empty():
		return _drop(report, "%s: slot entry without item id." % label)
	var amount := _to_int(entry.get("n"), 0)
	if amount < 1:
		return _drop(report, "%s: '%s' has an invalid amount." % [label, raw_id])
	var index := _to_int(entry.get("i"), -1)
	var item_id := StringName(raw_id)
	if options.item_aliases.has(item_id):
		item_id = StringName(options.item_aliases[item_id])
	elif options.item_aliases.has(String(item_id)):
		item_id = StringName(options.item_aliases[String(item_id)])
	var uid: Variant = entry.get("uid", "")
	if not uid is String:
		report.warn("%s: '%s' had an invalid uid; replaced." % [label, item_id])
		uid = ""
	if not uid.is_empty():
		if seen_uids.has(uid):
			return _drop(report, "%s: duplicate of unique item '%s' (uid %s) removed." % [label, item_id, uid])
		seen_uids[uid] = true
	var data := {}
	if entry.has("data"):
		var decoded: Variant = _decode_data(entry["data"])
		if decoded is Dictionary:
			data = decoded
		else:
			report.warn("%s: '%s' had unreadable data; cleared." % [label, item_id])
	var stack := IKItemStack.new(item_id, amount, uid, data)
	var rotated: Variant = entry.get("rot", false)
	stack.rotated = rotated is bool and rotated
	return [stack, index]


## Splits stacks above max_stack and fixes uids of unique items.
static func _split_to_limits(stack: IKItemStack, definition: IKItemDefinition, label: String,
		report: IKLoadReport, seen_uids: Dictionary) -> Array[IKItemStack]:
	var pieces: Array[IKItemStack] = []
	var limit := definition.get_effective_max_stack()
	if stack.amount > limit:
		report.warn("%s: '%s' x%d exceeds max stack %d; split." % [label, stack.item_id, stack.amount, limit])
	var remaining := stack.amount
	while remaining > 0:
		var piece := stack.copy()
		piece.amount = mini(limit, remaining)
		if not pieces.is_empty():
			piece.uid = ""
		remaining -= piece.amount
		pieces.append(piece)
	if definition.unique:
		for piece in pieces:
			if not piece.has_uid():
				piece.uid = IKUid.generate()
				seen_uids[piece.uid] = true
				if piece == pieces[0]:
					report.warn("%s: unique item '%s' had no uid; one was assigned." % [label, stack.item_id])
	return pieces


static func _relocate(container: IKContainer, slots: Array, stack: IKItemStack, report: IKLoadReport,
		occupancy: PackedInt32Array = PackedInt32Array()) -> void:
	var definition := container.database.get_item(stack.item_id) if container.database else null
	if definition != null and not stack.has_uid():
		var limit := definition.get_effective_max_stack()
		for existing in slots:
			if existing != null and existing.can_merge_with(stack) and existing.amount < limit:
				var merged := mini(limit - existing.amount, stack.amount)
				existing.amount += merged
				stack.amount -= merged
				if stack.amount == 0:
					return
	if container.is_grid():
		var spot := container._find_spot(occupancy, stack, definition)
		if spot >= 0:
			_put(container, slots, occupancy, spot, stack)
			return
		report.overflow.append({"container_id": container.container_id, "stack": stack})
		report.warn("%s: no room for '%s' x%d; moved to overflow." % [String(container.container_id), stack.item_id, stack.amount])
		return
	for i in slots.size():
		if slots[i] != null:
			continue
		var allowed := container._accepts(i, stack, definition) if definition != null \
			else container._slot_rules[i] == null
		if allowed:
			slots[i] = stack
			return
	report.overflow.append({"container_id": container.container_id, "stack": stack})
	report.warn("%s: no room for '%s' x%d; moved to overflow." % [String(container.container_id), stack.item_id, stack.amount])


static func _decode_data(value: Variant) -> Variant:
	if value is Dictionary and value.has("type") and value.has("args"):
		return JSON.to_native(value)
	# Hand-written plain JSON object: accepted as-is (numbers will be floats).
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return null


static func _to_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value):
		return int(value)
	return fallback


static func _drop(report: IKLoadReport, message: String) -> Array:
	report.dropped += 1
	report.warn(message)
	return []
