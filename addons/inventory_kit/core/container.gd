class_name IKContainer
extends RefCounted
## A fixed number of slots holding item stacks (bag, chest, equipment...).
##
## Every change goes through an [IKTransaction], so it is atomic and item totals
## are conserved. The helper methods ([method add], [method move]...) each run a
## one-operation transaction. Read methods return copies: editing a returned
## [IKItemStack] never changes the container.
##
## [b]Grid mode[/b] (optional, see [method set_grid_width]): slots become the cells
## of a grid, row by row, and items take [member IKItemDefinition.grid_size] cells
## (Diablo / Resident Evil style). A stack is stored at its top-left cell, its
## [i]anchor[/i]; the other cells it covers stay empty in the slot list but are
## taken (see [method get_anchor]). Classic slots stay the default.

## Slots whose content changed, after a successful commit.
signal slots_changed(slot_indices: PackedInt32Array)
## Net amount of an item that entered the container in one commit.
signal item_added(item_id: StringName, amount: int)
## Net amount of an item that left the container in one commit.
signal item_removed(item_id: StringName, amount: int)
## Emitted once per commit (or resize) that changed this container.
signal changed

## Stable id, used as the key in save files (e.g. &"player_bag").
var container_id: StringName
var database: IKItemDatabase
var rules: Array[IKContainerRule] = []

var _slots: Array = []
var _slot_rules: Array = []
var _revision: int = 0
var _grid_width := 0
var _occupancy_cache := PackedInt32Array()
var _occupancy_key := ""


func _init(p_container_id: StringName = &"", p_size: int = 0, p_database: IKItemDatabase = null,
		p_grid_width: int = 0) -> void:
	container_id = p_container_id
	database = p_database
	_slots.resize(maxi(0, p_size))
	_slot_rules.resize(maxi(0, p_size))
	if p_grid_width > 0:
		var result := set_grid_width(p_grid_width)
		if not result.ok:
			push_error("IKContainer '%s': %s" % [container_id, result.message])


## A grid container of [param width] x [param height] cells.
static func create_grid(p_container_id: StringName, width: int, height: int, p_database: IKItemDatabase) -> IKContainer:
	return IKContainer.new(p_container_id, maxi(0, width) * maxi(0, height), p_database, width)


# --- Reading -----------------------------------------------------------------

func size() -> int:
	return _slots.size()


func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < _slots.size()


## Copy of the stack in [param slot], or null if empty or out of range.
## In grid mode only the anchor (top-left cell) of an item holds its stack:
## use [method get_anchor] to find the item covering any cell.
func get_stack(slot: int) -> IKItemStack:
	if not is_valid_slot(slot) or _slots[slot] == null:
		return null
	return (_slots[slot] as IKItemStack).copy()


## In grid mode, false for every cell an item covers.
func is_slot_empty(slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	if _grid_width > 0:
		return _get_occupancy()[slot] < 0
	return _slots[slot] == null


func get_definition(slot: int) -> IKItemDefinition:
	if not is_valid_slot(slot) or _slots[slot] == null or database == null:
		return null
	return database.get_item((_slots[slot] as IKItemStack).item_id)


func count(item_id: StringName) -> int:
	var total := 0
	for stack in _slots:
		if stack != null and stack.item_id == item_id:
			total += stack.amount
	return total


func has(item_id: StringName, amount: int = 1) -> bool:
	return count(item_id) >= amount


## [param requirements] maps item ids to amounts, e.g. {&"wood": 4, &"rope": 1}.
func has_all(requirements: Dictionary) -> bool:
	for item_id in requirements:
		if count(StringName(item_id)) < int(requirements[item_id]):
			return false
	return true


func find_slots(item_id: StringName) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in _slots.size():
		if _slots[i] != null and _slots[i].item_id == item_id:
			result.append(i)
	return result


## In grid mode: number of free cells.
func get_free_slot_count() -> int:
	if _grid_width > 0:
		return _get_occupancy().count(-1)
	return _slots.count(null)


## In grid mode: first free cell.
func get_first_free_slot() -> int:
	if _grid_width > 0:
		return _get_occupancy().find(-1)
	return _slots.find(null)


## Item id -> total amount.
func get_totals() -> Dictionary:
	var totals := {}
	_accumulate_totals(_slots, totals)
	return totals


## Incremented on every committed change. Useful to detect stale UI state.
func get_revision() -> int:
	return _revision


func get_slot_rule(slot: int) -> IKSlotRule:
	if not is_valid_slot(slot):
		return null
	return _slot_rules[slot]


## True if [param stack] would be allowed in [param slot] (ignores what the slot holds).
func can_accept(slot: int, stack: IKItemStack) -> bool:
	if stack == null or not is_valid_slot(slot) or database == null:
		return false
	var definition := database.get_item(stack.item_id)
	return definition != null and _accepts(slot, stack, definition)


## Plain data view of every slot (null or dictionary). For tests and debugging.
func to_debug_array() -> Array:
	var result := []
	for stack in _slots:
		result.append(null if stack == null else stack.to_debug_dict())
	return result


# --- Grid mode ---------------------------------------------------------------

func is_grid() -> bool:
	return _grid_width > 0


## Columns of the grid, 0 for classic slots.
func get_grid_width() -> int:
	return _grid_width


## Rows of the grid, 0 for classic slots.
func get_grid_height() -> int:
	return _slots.size() / _grid_width if _grid_width > 0 else 0


## Cell coordinates of [param slot] (classic slots: one row).
func cell_of(slot: int) -> Vector2i:
	if _grid_width <= 0:
		return Vector2i(slot, 0)
	return Vector2i(slot % _grid_width, slot / _grid_width)


## Slot index of a cell, -1 if outside the grid.
func slot_of(cell: Vector2i) -> int:
	if _grid_width <= 0:
		return cell.x if cell.y == 0 and is_valid_slot(cell.x) else -1
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid_width or cell.y >= get_grid_height():
		return -1
	return cell.y * _grid_width + cell.x


## Slot of the stack covering [param slot] (itself for an anchor), or -1 if free.
## Classic slots: [param slot] if it holds a stack, else -1.
func get_anchor(slot: int) -> int:
	if not is_valid_slot(slot):
		return -1
	if _grid_width <= 0:
		return slot if _slots[slot] != null else -1
	return _get_occupancy()[slot]


## Cells taken by [param stack] in this container, with its rotation (1 x 1 for classic slots).
func get_size_of(stack: IKItemStack) -> Vector2i:
	if stack == null or _grid_width <= 0:
		return Vector2i.ONE
	return _size_of(stack)


## Cells taken by the item anchored at [param slot] (1 x 1 if empty or classic slots).
func get_item_size(slot: int) -> Vector2i:
	if not is_valid_slot(slot) or _slots[slot] == null:
		return Vector2i.ONE
	return get_size_of(_slots[slot])


## Every cell covered by the item covering [param slot] (empty if free).
func get_footprint(slot: int) -> PackedInt32Array:
	var anchor := get_anchor(slot)
	if anchor < 0:
		return PackedInt32Array()
	return _area(anchor, get_item_size(anchor))


## True if [param stack] (with its own rotation) fits with its top-left cell on
## [param slot] without covering any other item, and the rules accept it.
## [param ignore_slot]: an anchor to treat as empty (the item being moved).
func can_place(slot: int, stack: IKItemStack, ignore_slot: int = -1) -> bool:
	if stack == null or not is_valid_slot(slot) or database == null:
		return false
	var definition := database.get_item(stack.item_id)
	if definition == null or not _accepts(slot, stack, definition):
		return false
	var size := get_size_of(stack)
	if not _in_bounds(slot, size):
		return false
	var ignore := PackedInt32Array([ignore_slot]) if ignore_slot >= 0 else PackedInt32Array()
	return _area_free(_occupancy(_slots, ignore), slot, size)


## True if dropping [param stack] with its top-left cell on [param slot] can work:
## inside the grid, accepted by the rules, and covering at most one item (which
## it would merge with or swap with). The UI uses it for the drop preview.
func can_drop(slot: int, stack: IKItemStack) -> bool:
	if stack == null or not is_valid_slot(slot) or database == null:
		return false
	var definition := database.get_item(stack.item_id)
	if definition == null or not _accepts(slot, stack, definition):
		return false
	var size := get_size_of(stack)
	if not _in_bounds(slot, size):
		return false
	var occupancy := _get_occupancy() if _grid_width > 0 else _occupancy(_slots)
	return _area_anchors(occupancy, slot, size).size() <= 1


## Anchors of the items [param stack] would cover with its top-left cell on [param slot]
## (cells outside the grid are ignored). One item: a drop there merges or swaps.
func get_overlapping(slot: int, stack: IKItemStack, ignore_slot: int = -1) -> PackedInt32Array:
	if stack == null or not is_valid_slot(slot):
		return PackedInt32Array()
	var ignore := PackedInt32Array([ignore_slot]) if ignore_slot >= 0 else PackedInt32Array()
	return _area_anchors(_occupancy(_slots, ignore), slot, get_size_of(stack))


## Where [param stack] would go with automatic placement: the first cell (row by
## row) where it fits, as is, then turned if it can turn. Returns
## [code]{"slot": int, "rotated": bool}[/code], or an empty Dictionary if it fits nowhere.
## Classic slots: the first empty slot that accepts it.
func find_place(stack: IKItemStack) -> Dictionary:
	if stack == null or database == null:
		return {}
	var definition := database.get_item(stack.item_id)
	if definition == null:
		return {}
	var probe := stack.copy()
	var slot := _find_spot(_occupancy(_slots), probe, definition)
	if slot < 0:
		return {}
	return {"slot": slot, "rotated": probe.rotated}


## Switches to grid mode with [param width] columns (0 = back to classic slots).
## The size must be a multiple of the width, and current items must fit the grid
## without overlapping. Do it before showing the container in a view.
func set_grid_width(width: int) -> IKResult:
	if width < 0:
		return IKResult.failure(IKResult.Code.INVALID_ARGUMENT, "Grid width must be >= 0.")
	if width > 0 and _slots.size() % width != 0:
		return IKResult.failure(IKResult.Code.INVALID_ARGUMENT,
			"Size %d is not a multiple of the grid width %d." % [_slots.size(), width])
	var previous := _grid_width
	_grid_width = width
	_occupancy_key = ""
	if width > 0:
		var issues := _grid_issues(_slots)
		if not issues.is_empty():
			_grid_width = previous
			_occupancy_key = ""
			return IKResult.failure(IKResult.Code.SLOT_OCCUPIED, issues[0])
	if previous != width:
		changed.emit()
	return IKResult.success()


# --- Configuration -----------------------------------------------------------

## Fails if the slot currently holds a stack the new rule would reject.
func set_slot_rule(slot: int, rule: IKSlotRule) -> IKResult:
	if not is_valid_slot(slot):
		return IKResult.failure(IKResult.Code.SLOT_OUT_OF_RANGE, "Slot %d out of range." % slot)
	var stack: IKItemStack = _slots[slot]
	if stack != null and rule != null:
		var definition := database.get_item(stack.item_id) if database else null
		if definition == null or not rule.accepts(stack, definition):
			return IKResult.failure(IKResult.Code.RULE_REJECTED, "Slot %d holds an item the rule rejects." % slot)
	_slot_rules[slot] = rule
	return IKResult.success()


## Grows or shrinks the container. Shrinking fails if a removed slot is occupied.
## Grid mode: the size must stay a multiple of the width (rows are added or removed).
func resize(new_size: int) -> IKResult:
	if new_size < 0:
		return IKResult.failure(IKResult.Code.INVALID_ARGUMENT, "Size must be >= 0.")
	if _grid_width > 0:
		if new_size % _grid_width != 0:
			return IKResult.failure(IKResult.Code.INVALID_ARGUMENT,
				"Size %d is not a multiple of the grid width %d." % [new_size, _grid_width])
		var occupancy := _get_occupancy()
		for i in range(new_size, _slots.size()):
			if occupancy[i] >= 0:
				return IKResult.failure(IKResult.Code.SLOT_OCCUPIED, "Cell %d is not empty." % i)
	for i in range(new_size, _slots.size()):
		if _slots[i] != null:
			return IKResult.failure(IKResult.Code.SLOT_OCCUPIED, "Slot %d is not empty." % i)
	var old_size := _slots.size()
	var new_slots := _slots.duplicate()
	new_slots.resize(new_size)
	_slot_rules.resize(new_size)
	_apply_slots(new_slots)
	var touched := PackedInt32Array()
	for i in range(mini(old_size, new_size), maxi(old_size, new_size)):
		touched.append(i)
	if not touched.is_empty():
		slots_changed.emit(touched)
		changed.emit()
	return IKResult.success()


# --- Changes (one-operation transactions) ------------------------------------

func transaction() -> IKTransaction:
	return IKTransaction.new()


## Adds items, topping up existing stacks first. With [param allow_partial],
## what does not fit is reported in [member IKResult.remainder] instead of failing.
func add(item_id: StringName, amount: int = 1, allow_partial: bool = false, data: Dictionary = {}) -> IKResult:
	return IKTransaction.new().add(self, item_id, amount, allow_partial, data).commit()


func add_stack(stack: IKItemStack, allow_partial: bool = false) -> IKResult:
	return IKTransaction.new().add_stack(self, stack, allow_partial).commit()


func remove(item_id: StringName, amount: int = 1) -> IKResult:
	return IKTransaction.new().remove(self, item_id, amount).commit()


## [param amount] -1 removes the whole stack.
func remove_at(slot: int, amount: int = -1) -> IKResult:
	return IKTransaction.new().remove_at(self, slot, amount).commit()


## All-or-nothing removal of several items (crafting costs, quest hand-ins).
func try_consume(requirements: Dictionary) -> IKResult:
	return IKTransaction.new().consume(self, requirements).commit()


## Move within this container: place, merge or swap.
func move(from_slot: int, to_slot: int, amount: int = -1) -> IKResult:
	return IKTransaction.new().move(self, from_slot, self, to_slot, amount).commit()


func move_to(from_slot: int, target: IKContainer, to_slot: int, amount: int = -1) -> IKResult:
	return IKTransaction.new().move(self, from_slot, target, to_slot, amount).commit()


## Quick move to another container: merges first, then fills empty slots.
func transfer_to(from_slot: int, target: IKContainer, amount: int = -1) -> IKResult:
	return IKTransaction.new().transfer(self, from_slot, target, amount).commit()


## Merges [param changes] into the per-copy data of a slot (null removes a key).
func set_data(slot: int, changes: Dictionary) -> IKResult:
	return IKTransaction.new().set_data(self, slot, changes).commit()


## Splits [param amount] off into [param to_slot] (-1 = first suitable empty slot).
func split(slot: int, amount: int, to_slot: int = -1) -> IKResult:
	return IKTransaction.new().split(self, slot, amount, to_slot).commit()


## Turns the item covering [param slot] a quarter turn (grid mode; its top-left cell stays).
func rotate(slot: int) -> IKResult:
	return IKTransaction.new().rotate(self, slot).commit()


# --- Internal (used by IKTransaction) ----------------------------------------

func _accepts(slot: int, stack: IKItemStack, definition: IKItemDefinition) -> bool:
	var slot_rule: IKSlotRule = _slot_rules[slot]
	if slot_rule != null and not slot_rule.accepts(stack, definition):
		return false
	for rule in rules:
		if rule != null and not rule.accepts(stack, definition):
			return false
	return true


func _apply_slots(new_slots: Array) -> void:
	# Always replace the array, never mutate it: open transactions keep a
	# reference to the previous one as their "before" state.
	_slots = new_slots
	_revision += 1


func _notify(slot_indices: PackedInt32Array, before: Array, after: Array) -> void:
	if slot_indices.is_empty():
		return
	var before_totals := {}
	var after_totals := {}
	_accumulate_totals_at(before, slot_indices, before_totals)
	_accumulate_totals_at(after, slot_indices, after_totals)
	slots_changed.emit(slot_indices)
	for item_id in after_totals:
		var gained: int = after_totals[item_id] - before_totals.get(item_id, 0)
		if gained > 0:
			item_added.emit(item_id, gained)
	for item_id in before_totals:
		var lost: int = before_totals[item_id] - after_totals.get(item_id, 0)
		if lost > 0:
			item_removed.emit(item_id, lost)
	changed.emit()


static func _accumulate_totals_at(slots: Array, indices: PackedInt32Array, into: Dictionary) -> void:
	for i in indices:
		var stack: IKItemStack = slots[i]
		if stack != null:
			into[stack.item_id] = into.get(stack.item_id, 0) + stack.amount


static func _accumulate_totals(slots: Array, into: Dictionary) -> void:
	for stack in slots:
		if stack != null:
			into[stack.item_id] = into.get(stack.item_id, 0) + stack.amount


# --- Grid internals (work on any slot array: the container's or a transaction's) ---

## Cells of a stack here, with its rotation. Unknown items take one cell.
func _size_of(stack: IKItemStack) -> Vector2i:
	if _grid_width <= 0:
		return Vector2i.ONE
	var definition := database.get_item(stack.item_id) if database != null else null
	if definition == null:
		return Vector2i.ONE
	return definition.get_grid_size(stack.rotated)


func _in_bounds(slot: int, size: Vector2i) -> bool:
	if not is_valid_slot(slot):
		return false
	if _grid_width <= 0:
		return size == Vector2i.ONE
	var cell := cell_of(slot)
	return cell.x + size.x <= _grid_width and cell.y + size.y <= get_grid_height()


## Cells of the area (only those inside the grid).
func _area(slot: int, size: Vector2i) -> PackedInt32Array:
	var cells := PackedInt32Array()
	if not is_valid_slot(slot):
		return cells
	if _grid_width <= 0:
		cells.append(slot)
		return cells
	var origin := cell_of(slot)
	var height := get_grid_height()
	for y in range(origin.y, mini(origin.y + size.y, height)):
		for x in range(origin.x, mini(origin.x + size.x, _grid_width)):
			cells.append(y * _grid_width + x)
	return cells


## Cell -> anchor slot of the stack covering it (-1 = free). Stacks at [param ignore] are skipped.
## Classic slots: each slot covers itself.
func _occupancy(slots: Array, ignore: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var occupancy := PackedInt32Array()
	occupancy.resize(slots.size())
	occupancy.fill(-1)
	for i in slots.size():
		if slots[i] == null or ignore.has(i):
			continue
		if _grid_width <= 0:
			occupancy[i] = i
			continue
		for cell in _area(i, _size_of(slots[i])):
			if occupancy[cell] < 0:
				occupancy[cell] = i
	return occupancy


func _get_occupancy() -> PackedInt32Array:
	var key := "%d:%d:%d" % [_revision, database.get_instance_id() if database != null else 0, _grid_width]
	if key != _occupancy_key or _occupancy_cache.size() != _slots.size():
		_occupancy_cache = _occupancy(_slots)
		_occupancy_key = key
	return _occupancy_cache


func _area_free(occupancy: PackedInt32Array, slot: int, size: Vector2i) -> bool:
	if not _in_bounds(slot, size):
		return false
	for cell in _area(slot, size):
		if occupancy[cell] >= 0:
			return false
	return true


func _area_anchors(occupancy: PackedInt32Array, slot: int, size: Vector2i) -> PackedInt32Array:
	var anchors := PackedInt32Array()
	for cell in _area(slot, size):
		var anchor := occupancy[cell]
		if anchor >= 0 and not anchors.has(anchor):
			anchors.append(anchor)
	return anchors


func _mark_area(occupancy: PackedInt32Array, slot: int, size: Vector2i) -> void:
	for cell in _area(slot, size):
		occupancy[cell] = slot


## First slot where [param stack] fits (its rotation first, then turned if it can
## turn), or -1. Sets [member IKItemStack.rotated] of [param stack] to the one that fits.
func _find_spot(occupancy: PackedInt32Array, stack: IKItemStack, definition: IKItemDefinition) -> int:
	var original := stack.rotated
	var orientations := [original]
	if _grid_width > 0 and definition != null and definition.is_rotatable():
		orientations.append(not original)
	for rotated in orientations:
		stack.rotated = rotated
		var size := definition.get_grid_size(rotated) if definition != null and _grid_width > 0 else Vector2i.ONE
		for i in occupancy.size():
			if occupancy[i] >= 0 or not _area_free(occupancy, i, size):
				continue
			var allowed := _accepts(i, stack, definition) if definition != null else _slot_rules[i] == null
			if allowed:
				return i
	stack.rotated = original
	return -1


## Overlapping or out-of-grid stacks in [param slots] (empty = valid layout).
func _grid_issues(slots: Array) -> PackedStringArray:
	var issues := PackedStringArray()
	if _grid_width <= 0:
		return issues
	var taken := PackedInt32Array()
	taken.resize(slots.size())
	taken.fill(-1)
	for i in slots.size():
		if slots[i] == null:
			continue
		var size := _size_of(slots[i])
		if not _in_bounds(i, size):
			issues.append("'%s' at cell %d does not fit inside the grid." % [slots[i].item_id, i])
			continue
		for cell in _area(i, size):
			if taken[cell] >= 0:
				issues.append("'%s' at cell %d overlaps the item at cell %d." % [slots[i].item_id, i, taken[cell]])
				break
			taken[cell] = i
	return issues
