class_name IKSorter
extends RefCounted
## Sorts a container in one atomic transaction: merges matching stacks, then
## orders them. Slots that have a slot rule (equipment) and items missing from
## the database are left in place.

enum Mode {
	## Category, then name.
	CATEGORY,
	## Display name (or id).
	NAME,
	## Largest stacks first, then name.
	AMOUNT,
}


## [param category_order] lists categories in the wanted order (e.g. weapons
## first); categories not listed come after, alphabetically.
static func sort(container: IKContainer, mode: Mode = Mode.CATEGORY, category_order: Array[StringName] = []) -> IKResult:
	if container.is_grid():
		return _sort_grid(container, mode, category_order)
	var free_slots := PackedInt32Array()
	var stacks: Array[IKItemStack] = []
	var layout := []
	layout.resize(container.size())
	for i in container.size():
		var stack := container.get_stack(i)
		if container.get_slot_rule(i) != null or (stack != null and container.get_definition(i) == null):
			layout[i] = stack  # fixed slot or unknown item: keep as is
			continue
		free_slots.append(i)
		if stack != null:
			stacks.append(stack)
	var merged := _merge(stacks, container.database)
	var keyed := []
	for stack in merged:
		keyed.append([_key(stack, container.database.get_item(stack.item_id), mode, category_order), stack])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in free_slots.size():
		layout[free_slots[i]] = keyed[i][1] if i < keyed.size() else null
	return IKTransaction.new().rearrange(container, layout).commit()


## Grid containers: merges, sorts, then packs the items again from the top-left
## corner (row by row, turning items when that is the only way they fit). If the
## sorted order cannot be packed, biggest items go first; if that fails too,
## nothing changes (CONTAINER_FULL). Unknown items stay where they are.
static func _sort_grid(container: IKContainer, mode: Mode, category_order: Array[StringName]) -> IKResult:
	var fixed := []
	fixed.resize(container.size())
	var stacks: Array[IKItemStack] = []
	for i in container.size():
		var stack := container.get_stack(i)
		if stack == null:
			continue
		if container.get_definition(i) == null:
			fixed[i] = stack
		else:
			stack.rotated = false
			stacks.append(stack)
	var keyed := []
	for stack in _merge(stacks, container.database):
		keyed.append([_key(stack, container.database.get_item(stack.item_id), mode, category_order), stack])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var ordered: Array[IKItemStack] = []
	for pair in keyed:
		ordered.append(pair[1])
	var layout := _pack(container, fixed, ordered)
	if layout.is_empty():
		var by_area := ordered.duplicate()
		by_area.sort_custom(func(a: IKItemStack, b: IKItemStack) -> bool:
			return _area_of(container, a) > _area_of(container, b))
		layout = _pack(container, fixed, by_area)
	if layout.is_empty():
		return IKResult.failure(IKResult.Code.CONTAINER_FULL, "The items cannot be packed in sorted order.")
	return IKTransaction.new().rearrange(container, layout).commit()


## Layout with [param stacks] placed first-fit around [param fixed], or [] if one does not fit.
static func _pack(container: IKContainer, fixed: Array, stacks: Array[IKItemStack]) -> Array:
	var layout := fixed.duplicate()
	var occupancy := container._occupancy(layout)
	for original in stacks:
		var stack := original.copy()
		stack.rotated = false
		var definition := container.database.get_item(stack.item_id)
		var spot := container._find_spot(occupancy, stack, definition)
		if spot < 0:
			return []
		layout[spot] = stack
		container._mark_area(occupancy, spot, container.get_size_of(stack))
	return layout


static func _area_of(container: IKContainer, stack: IKItemStack) -> int:
	var cells := container.database.get_item(stack.item_id).get_grid_size()
	return cells.x * cells.y


## Combines stacks that can merge, up to each item's max stack.
static func _merge(stacks: Array[IKItemStack], database: IKItemDatabase) -> Array[IKItemStack]:
	var result: Array[IKItemStack] = []
	for stack in stacks:
		var definition := database.get_item(stack.item_id) if database else null
		var limit := definition.get_effective_max_stack() if definition != null else stack.amount
		for existing in result:
			if stack.amount == 0:
				break
			if existing.can_merge_with(stack) and existing.amount < limit:
				var moved := mini(limit - existing.amount, stack.amount)
				existing.amount += moved
				stack.amount -= moved
		if stack.amount > 0:
			result.append(stack)
	return result


static func _key(stack: IKItemStack, definition: IKItemDefinition, mode: Mode, category_order: Array[StringName]) -> String:
	var name := String(stack.item_id)
	var category := ""
	if definition != null:
		name = definition.display_name if not definition.display_name.is_empty() else String(definition.id)
		var rank := category_order.find(definition.category)
		# Listed categories first, in list order; the rest alphabetically after them.
		category = ("%04d" % rank) if rank >= 0 else "~" + String(definition.category)
	# Fixed-width amount so string order equals numeric order (descending).
	var amount_desc := "%06d" % (999999 - stack.amount)
	var tie := "%s|%s" % [String(stack.item_id), stack.uid]
	match mode:
		Mode.NAME:
			return "%s|%s|%s" % [name.to_lower(), amount_desc, tie]
		Mode.AMOUNT:
			return "%s|%s|%s" % [amount_desc, name.to_lower(), tie]
	return "%s|%s|%s|%s" % [category.to_lower(), name.to_lower(), amount_desc, tie]
