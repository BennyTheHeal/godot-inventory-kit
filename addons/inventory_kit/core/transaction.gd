class_name IKTransaction
extends RefCounted
## Atomic batch of inventory operations across one or more containers.
##
## Operations run on private working copies (copy-on-write: only the slots an
## operation changes are copied, so cost does not grow with container size).
## [method commit] validates the final
## state (slot rules, stack sizes, unique ids, conservation of item totals) and
## then applies every container at once, or applies nothing.
##
## After the first failing operation the transaction is poisoned: later
## operations are ignored and [method commit] returns that first error.
## Signals are emitted only after everything has been applied.
## [codeblock]
## var result := IKTransaction.new() \
##     .consume(bag, {&"wood": 4, &"rope": 1}) \
##     .add(bag, &"bow", 1) \
##     .commit()
## [/codeblock]

const Code := IKResult.Code


class _Work:
	var container: IKContainer
	var revision: int
	var before: Array
	var slots: Array


var _work: Dictionary = {}  # container instance id -> _Work
var _owned: Dictionary = {}  # instance ids of stacks this transaction may modify
var _order: Array[int] = []  # touch order, for deterministic signal order
var _delta: Dictionary = {}  # item_id -> declared change of the total amount
var _error: IKResult = null
var _closed := false
var _remainder := 0


## True once an operation has failed; [method commit] will return that error.
func has_failed() -> bool:
	return _error != null


func get_error() -> IKResult:
	return _error


# --- Operations ----------------------------------------------------------------

func add(container: IKContainer, item_id: StringName, amount: int = 1, allow_partial: bool = false, data: Dictionary = {}) -> IKTransaction:
	if not _can_run():
		return self
	if container == null or amount <= 0:
		return _fail(Code.INVALID_ARGUMENT, "add() needs a container and a positive amount.")
	var definition := _definition(container, item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % item_id)
	return _place(container, IKItemStack.new(item_id, amount, "", data), definition, allow_partial)


## Adds a copy of [param stack], keeping its uid and data (loot, rewards, trades).
func add_stack(container: IKContainer, stack: IKItemStack, allow_partial: bool = false) -> IKTransaction:
	if not _can_run():
		return self
	if container == null or stack == null or stack.amount <= 0:
		return _fail(Code.INVALID_ARGUMENT, "add_stack() needs a container and a non-empty stack.")
	var definition := _definition(container, stack.item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	return _place(container, stack.copy(), definition, allow_partial)


## Removes [param amount] items, starting from the last slots.
func remove(container: IKContainer, item_id: StringName, amount: int = 1) -> IKTransaction:
	if not _can_run():
		return self
	if container == null or amount <= 0:
		return _fail(Code.INVALID_ARGUMENT, "remove() needs a container and a positive amount.")
	var slots := _slots_of(container)
	var available := 0
	for stack in slots:
		if stack != null and stack.item_id == item_id:
			available += stack.amount
	if available < amount:
		return _fail(Code.NOT_ENOUGH_ITEMS, "Needs %d '%s', has %d." % [amount, item_id, available])
	var remaining := amount
	for i in range(slots.size() - 1, -1, -1):
		if remaining == 0:
			break
		if slots[i] == null or slots[i].item_id != item_id:
			continue
		var stack := _own(slots, i)
		var taken := mini(stack.amount, remaining)
		stack.amount -= taken
		remaining -= taken
		if stack.amount == 0:
			slots[i] = null
	_add_delta(item_id, -amount)
	return self


## Removes from one slot. [param amount] -1 removes the whole stack.
func remove_at(container: IKContainer, slot: int, amount: int = -1) -> IKTransaction:
	if not _can_run():
		return self
	if container == null:
		return _fail(Code.INVALID_ARGUMENT, "remove_at() needs a container.")
	var slots := _slots_of(container)
	if not _check_slot(slots, slot):
		return self
	slot = _resolve(container, slots, slot)
	var stack: IKItemStack = slots[slot]
	if stack == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % slot)
	var taken := stack.amount if amount < 0 else amount
	if taken == 0 or taken > stack.amount:
		return _fail(Code.NOT_ENOUGH_ITEMS, "Slot %d holds %d, cannot remove %d." % [slot, stack.amount, taken])
	stack = _own(slots, slot)
	stack.amount -= taken
	if stack.amount == 0:
		slots[slot] = null
	_add_delta(stack.item_id, -taken)
	return self


## All-or-nothing removal: {&"wood": 4, &"rope": 1}.
func consume(container: IKContainer, requirements: Dictionary) -> IKTransaction:
	for item_id in requirements:
		var amount := int(requirements[item_id])
		if amount <= 0:
			return _fail(Code.INVALID_ARGUMENT, "Requirement for '%s' must be positive." % item_id)
		remove(container, StringName(item_id), amount)
	return self


## Moves a stack (or part of it, [param amount] -1 = all) to a slot.
## Empty target: place. Same item: merge up to max stack, the rest stays.
## Different item: swap (whole stack only, both slot rules must accept).
func move(from: IKContainer, from_slot: int, to: IKContainer, to_slot: int, amount: int = -1) -> IKTransaction:
	if not _can_run():
		return self
	if from == null or to == null:
		return _fail(Code.INVALID_ARGUMENT, "move() needs two containers.")
	if from.is_grid() or to.is_grid():
		return _move_grid(from, from_slot, to, to_slot, amount)
	var source := _slots_of(from)
	var target := _slots_of(to)
	if not _check_slot(source, from_slot) or not _check_slot(target, to_slot):
		return self
	var stack: IKItemStack = source[from_slot]
	if stack == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % from_slot)
	if from == to and from_slot == to_slot:
		return self
	var moved := stack.amount if amount < 0 else amount
	if moved <= 0 or moved > stack.amount:
		return _fail(Code.INVALID_ARGUMENT, "Cannot move %d from a stack of %d." % [moved, stack.amount])
	var definition := _definition(to, stack.item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	var max_stack := definition.get_effective_max_stack()
	var existing: IKItemStack = target[to_slot]

	if existing == null:
		if moved > max_stack:
			return _fail(Code.SLOT_FULL, "At most %d '%s' fit in one slot." % [max_stack, stack.item_id])
		var moving := _mark(stack.copy())
		moving.amount = moved
		if not to._accepts(to_slot, moving, definition):
			return _fail(Code.RULE_REJECTED, "Slot %d does not accept '%s'." % [to_slot, stack.item_id])
		target[to_slot] = moving
		stack = _own(source, from_slot)
		stack.amount -= moved
		if stack.amount == 0:
			source[from_slot] = null
		return self

	if existing.can_merge_with(stack):
		var room := max_stack - existing.amount
		if room <= 0:
			return _fail(Code.SLOT_FULL, "Slot %d is full." % to_slot)
		var merged := mini(room, moved)
		existing = _own(target, to_slot)
		stack = _own(source, from_slot)
		existing.amount += merged
		stack.amount -= merged
		if stack.amount == 0:
			source[from_slot] = null
		return self

	if moved != stack.amount:
		return _fail(Code.NOT_MERGEABLE, "Cannot drop part of a stack on a different item.")
	var other_definition := _definition(from, existing.item_id)
	if other_definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % existing.item_id)
	if not to._accepts(to_slot, stack, definition) or not from._accepts(from_slot, existing, other_definition):
		return _fail(Code.RULE_REJECTED, "Swap rejected by a slot rule.")
	target[to_slot] = stack
	source[from_slot] = existing
	return self


## Changes the per-copy data of the stack in [param slot] (durability, charges,
## enchantments...). Entries of [param changes] are merged in; a null value removes
## that key. Amount and uid never change.
## [codeblock]
## bag.set_data(slot, {"durability": stack.data.durability - 1})
## [/codeblock]
func set_data(container: IKContainer, slot: int, changes: Dictionary) -> IKTransaction:
	if not _can_run():
		return self
	if container == null:
		return _fail(Code.INVALID_ARGUMENT, "set_data() needs a container.")
	var slots := _slots_of(container)
	if not _check_slot(slots, slot):
		return self
	slot = _resolve(container, slots, slot)
	if slots[slot] == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % slot)
	var stack := _own(slots, slot)
	for key in changes:
		if changes[key] == null:
			stack.data.erase(key)
		else:
			stack.data[key] = changes[key].duplicate(true) if changes[key] is Dictionary or changes[key] is Array else changes[key]
	return self


## Splits [param amount] off a stack into an empty slot (-1 = first suitable one).
func split(container: IKContainer, slot: int, amount: int, to_slot: int = -1) -> IKTransaction:
	if not _can_run():
		return self
	if container == null:
		return _fail(Code.INVALID_ARGUMENT, "split() needs a container.")
	var slots := _slots_of(container)
	if not _check_slot(slots, slot):
		return self
	slot = _resolve(container, slots, slot)
	var stack: IKItemStack = slots[slot]
	if stack == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % slot)
	if stack.has_uid() or stack.amount < 2:
		return _fail(Code.NOT_SPLITTABLE, "Slot %d cannot be split." % slot)
	if amount <= 0 or amount >= stack.amount:
		return _fail(Code.INVALID_ARGUMENT, "Split amount must be between 1 and %d." % (stack.amount - 1))
	if container.is_grid():
		return _split_grid(container, slots, slot, amount, to_slot)
	if to_slot < 0:
		var definition := _definition(container, stack.item_id)
		for i in slots.size():
			if slots[i] == null and definition != null and container._accepts(i, stack, definition):
				to_slot = i
				break
		if to_slot < 0:
			return _fail(Code.CONTAINER_FULL, "No empty slot to split into.")
	elif not _check_slot(slots, to_slot):
		return self
	elif slots[to_slot] != null:
		return _fail(Code.SLOT_OCCUPIED, "Slot %d is not empty." % to_slot)
	return move(container, slot, container, to_slot, amount)


## Quick move into another container: tops up matching stacks, then empty slots.
## Moves as much as fits; the rest stays and is reported as remainder.
func transfer(from: IKContainer, from_slot: int, to: IKContainer, amount: int = -1) -> IKTransaction:
	if not _can_run():
		return self
	if from == null or to == null or from == to:
		return _fail(Code.INVALID_ARGUMENT, "transfer() needs two different containers.")
	var source := _slots_of(from)
	if not _check_slot(source, from_slot):
		return self
	from_slot = _resolve(from, source, from_slot)
	var stack: IKItemStack = source[from_slot]
	if stack == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % from_slot)
	var requested := stack.amount if amount < 0 else amount
	if requested <= 0 or requested > stack.amount:
		return _fail(Code.INVALID_ARGUMENT, "Cannot transfer %d from a stack of %d." % [requested, stack.amount])
	var definition := _definition(to, stack.item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	var max_stack := definition.get_effective_max_stack()
	var target := _slots_of(to)
	var remaining := requested
	for i in target.size():
		if remaining == 0:
			break
		var existing: IKItemStack = target[i]
		if existing != null and existing.can_merge_with(stack):
			var merged := mini(max_stack - existing.amount, remaining)
			if merged > 0:
				_own(target, i).amount += merged
				remaining -= merged
	if to.is_grid():
		var occupancy := to._occupancy(target)
		while remaining > 0:
			var piece := _mark(stack.copy())
			piece.amount = mini(max_stack, remaining)
			var spot := to._find_spot(occupancy, piece, definition)
			if spot < 0:
				break
			target[spot] = piece
			to._mark_area(occupancy, spot, to._size_of(piece))
			remaining -= piece.amount
	for i in target.size():
		if remaining == 0 or to.is_grid():
			break
		if target[i] != null:
			continue
		var moving := _mark(stack.copy())
		moving.amount = mini(max_stack, remaining)
		if not to._accepts(i, moving, definition):
			continue
		target[i] = moving
		remaining -= moving.amount
	var moved := requested - remaining
	if moved == 0:
		return _fail(Code.CONTAINER_FULL, "No room for '%s'." % stack.item_id)
	stack = _own(source, from_slot)
	stack.amount -= moved
	if stack.amount == 0:
		source[from_slot] = null
	_remainder += remaining
	return self


## Turns the item covering [param slot] a quarter turn, keeping its top-left cell
## (grid mode). Square items do not change; items with
## [member IKItemDefinition.can_rotate] off are refused. In a container with
## classic slots (the cursor) only the [member IKItemStack.rotated] flag changes.
func rotate(container: IKContainer, slot: int) -> IKTransaction:
	if not _can_run():
		return self
	if container == null:
		return _fail(Code.INVALID_ARGUMENT, "rotate() needs a container.")
	var slots := _slots_of(container)
	if not _check_slot(slots, slot):
		return self
	slot = _resolve(container, slots, slot)
	var stack: IKItemStack = slots[slot]
	if stack == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % slot)
	var definition := _definition(container, stack.item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	if not definition.can_rotate:
		_fail(Code.INVALID_ARGUMENT, "'%s' cannot be turned." % stack.item_id)
		_error.player_text = "This item cannot be turned."
		return self
	if not definition.is_rotatable():
		return self  # square: turning it changes nothing
	if container.is_grid():
		var occupancy := container._occupancy(slots, PackedInt32Array([slot]))
		if not container._area_free(occupancy, slot, definition.get_grid_size(not stack.rotated)):
			return _fail_fit(Code.SLOT_OCCUPIED, "No room to turn '%s' at cell %d." % [stack.item_id, slot])
	stack = _own(slots, slot)
	stack.rotated = not stack.rotated
	return self


## Replaces the whole content of [param container] with [param slots] (stacks
## or null, same size). For sorting and custom layouts: the usual checks still
## apply, so items can be rearranged, merged or split but never created or lost.
func rearrange(container: IKContainer, slots: Array) -> IKTransaction:
	if not _can_run():
		return self
	if container == null:
		return _fail(Code.INVALID_ARGUMENT, "rearrange() needs a container.")
	var work_slots := _slots_of(container)
	if slots.size() != work_slots.size():
		return _fail(Code.INVALID_ARGUMENT, "rearrange() needs exactly %d slots." % work_slots.size())
	for i in slots.size():
		var stack: Variant = slots[i]
		if stack != null and not stack is IKItemStack:
			return _fail(Code.INVALID_ARGUMENT, "Slot %d is not an IKItemStack." % i)
		work_slots[i] = _mark((stack as IKItemStack).copy()) if stack != null else null
	return self


# --- Commit ----------------------------------------------------------------------

func commit() -> IKResult:
	if _closed:
		return IKResult.failure(Code.TRANSACTION_CLOSED, "This transaction was already committed.")
	_closed = true
	if _error != null:
		return _error

	for key in _order:
		var work: _Work = _work[key]
		if work.container._revision != work.revision:
			return IKResult.failure(Code.CONCURRENT_MODIFICATION,
				"Container '%s' changed after this transaction started." % work.container.container_id)

	var changes := {}
	var before_totals := {}
	var after_totals := {}
	var seen_uids := {}
	var leaving_uids := {}
	for key in _order:
		var work: _Work = _work[key]
		var changed := PackedInt32Array()
		for i in work.slots.size():
			# Same object: never modified (modified stacks are private copies).
			if not is_same(work.before[i], work.slots[i]) and not IKItemStack.same(work.before[i], work.slots[i]):
				changed.append(i)
		for i in changed:
			if work.slots[i] != null:
				var invalid := _validate_stack(work.container, i, work.slots[i])
				if invalid != null:
					return invalid
		if work.container.is_grid() and not changed.is_empty():
			var issues := work.container._grid_issues(work.slots)
			if not issues.is_empty():
				return IKResult.failure(Code.INVARIANT_VIOLATION,
					"Container '%s': %s" % [work.container.container_id, issues[0]])
		for rule in work.container.rules:
			if rule != null and not rule.validate_change(work.before, work.slots, work.container.database):
				var refused := IKResult.failure(Code.RULE_REJECTED,
					"Container '%s' rejected the result." % work.container.container_id)
				refused.player_text = rule.refusal_text
				return refused
		for i in changed:
			var after: IKItemStack = work.slots[i]
			if after != null and after.has_uid():
				if seen_uids.has(after.uid):
					return IKResult.failure(Code.INVARIANT_VIOLATION, "Duplicate uid %s." % after.uid)
				seen_uids[after.uid] = true
			var previous: IKItemStack = work.before[i]
			if previous != null and previous.has_uid():
				leaving_uids[previous.uid] = true
		# Unchanged slots are identical before and after: only changed ones can move totals.
		IKContainer._accumulate_totals_at(work.before, changed, before_totals)
		IKContainer._accumulate_totals_at(work.slots, changed, after_totals)
		changes[key] = changed

	# A uid that did not come from one of the changed slots must not exist elsewhere.
	var fresh_uids := {}
	for uid in seen_uids:
		if not leaving_uids.has(uid):
			fresh_uids[uid] = true
	if not fresh_uids.is_empty():
		for key in _order:
			var work: _Work = _work[key]
			var changed_set := {}
			for i in changes[key]:
				changed_set[i] = true
			for i in work.before.size():
				var stack: IKItemStack = work.before[i]
				if stack != null and stack.has_uid() and fresh_uids.has(stack.uid) and not changed_set.has(i):
					return IKResult.failure(Code.INVARIANT_VIOLATION, "Duplicate uid %s." % stack.uid)

	var item_ids := {}
	for item_id in before_totals:
		item_ids[item_id] = true
	for item_id in after_totals:
		item_ids[item_id] = true
	for item_id in _delta:
		item_ids[item_id] = true
	for item_id in item_ids:
		var actual: int = after_totals.get(item_id, 0) - before_totals.get(item_id, 0)
		var declared: int = _delta.get(item_id, 0)
		if actual != declared:
			return IKResult.failure(Code.INVARIANT_VIOLATION,
				"Total of '%s' changed by %d instead of %d." % [item_id, actual, declared])

	for key in _order:
		var work: _Work = _work[key]
		work.container._apply_slots(work.slots)
	for key in _order:
		var work: _Work = _work[key]
		work.container._notify(changes[key], work.before, work.slots)
	return IKResult.success(_remainder)


# --- Internal ----------------------------------------------------------------------

func _can_run() -> bool:
	return _error == null and not _closed


func _fail(error_code: IKResult.Code, message: String) -> IKTransaction:
	if _error == null:
		_error = IKResult.failure(error_code, message)
	return self


func _slots_of(container: IKContainer) -> Array:
	var key := container.get_instance_id()
	if _work.has(key):
		return (_work[key] as _Work).slots
	var work := _Work.new()
	work.container = container
	work.revision = container._revision
	work.before = container._slots
	work.slots = work.before.duplicate()  # shares the stacks until one is modified (see _own)
	_work[key] = work
	_order.append(key)
	return work.slots


## The stack in [code]slots[slot][/code], made safe to modify: a stack still shared
## with the container is replaced by a private copy first.
func _own(slots: Array, slot: int) -> IKItemStack:
	var stack: IKItemStack = slots[slot]
	if stack != null and not _owned.has(stack.get_instance_id()):
		stack = _mark(stack.copy())
		slots[slot] = stack
	return stack


func _mark(stack: IKItemStack) -> IKItemStack:
	_owned[stack.get_instance_id()] = true
	return stack


func _check_slot(slots: Array, slot: int) -> bool:
	if slot < 0 or slot >= slots.size():
		_fail(Code.SLOT_OUT_OF_RANGE, "Slot %d out of range (size %d)." % [slot, slots.size()])
		return false
	return true


func _definition(container: IKContainer, item_id: StringName) -> IKItemDefinition:
	if container.database == null:
		return null
	return container.database.get_item(item_id)


func _add_delta(item_id: StringName, amount: int) -> void:
	_delta[item_id] = _delta.get(item_id, 0) + amount


## The anchor of the item covering [param slot] in a grid container (the slot itself otherwise).
func _resolve(container: IKContainer, slots: Array, slot: int) -> int:
	if container.is_grid() and slot >= 0 and slot < slots.size() and slots[slot] == null:
		var anchor := container._occupancy(slots)[slot]
		if anchor >= 0:
			return anchor
	return slot


## Like [method _fail], with the player text for placements that do not fit.
func _fail_fit(error_code: IKResult.Code, message: String) -> IKTransaction:
	if _error == null:
		_fail(error_code, message)
		_error.player_text = "It does not fit there."
	return self


## Grid-aware move (at least one of the containers is a grid). [param to_slot] is
## the cell for the top-left corner of the item. Free cells: place. Exactly one item
## under it: merge if possible, else swap (that item goes to [param from_slot]).
func _move_grid(from: IKContainer, from_slot: int, to: IKContainer, to_slot: int, amount: int) -> IKTransaction:
	var source := _slots_of(from)
	var target := _slots_of(to)
	if not _check_slot(source, from_slot) or not _check_slot(target, to_slot):
		return self
	from_slot = _resolve(from, source, from_slot)
	var stack: IKItemStack = source[from_slot]
	if stack == null:
		return _fail(Code.SLOT_EMPTY, "Slot %d is empty." % from_slot)
	if from == to and from_slot == to_slot:
		return self
	var moved := stack.amount if amount < 0 else amount
	if moved <= 0 or moved > stack.amount:
		return _fail(Code.INVALID_ARGUMENT, "Cannot move %d from a stack of %d." % [moved, stack.amount])
	var definition := _definition(to, stack.item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	var max_stack := definition.get_effective_max_stack()
	var whole := moved == stack.amount
	var same := from == to
	var size := to._size_of(stack)
	if not to._in_bounds(to_slot, size):
		return _fail_fit(Code.SLOT_OUT_OF_RANGE, "'%s' (%dx%d) does not fit at cell %d." % [stack.item_id, size.x, size.y, to_slot])
	var ignore := PackedInt32Array([from_slot]) if same and whole else PackedInt32Array()
	var others := to._area_anchors(to._occupancy(target, ignore), to_slot, size)

	if others.is_empty():
		if moved > max_stack:
			return _fail(Code.SLOT_FULL, "At most %d '%s' fit in one slot." % [max_stack, stack.item_id])
		var moving := _mark(stack.copy())
		moving.amount = moved
		if not to._accepts(to_slot, moving, definition):
			return _fail(Code.RULE_REJECTED, "Slot %d does not accept '%s'." % [to_slot, stack.item_id])
		if whole:
			source[from_slot] = null
		else:
			_own(source, from_slot).amount -= moved
		target[to_slot] = moving
		return self

	if others.size() > 1:
		return _fail_fit(Code.SLOT_OCCUPIED, "'%s' at cell %d would cover %d items." % [stack.item_id, to_slot, others.size()])
	var other_slot := others[0]
	var existing: IKItemStack = target[other_slot]
	if existing.can_merge_with(stack):
		if same and other_slot == from_slot:
			return self  # part of a stack dropped on itself
		var room := max_stack - existing.amount
		if room <= 0:
			return _fail(Code.SLOT_FULL, "Slot %d is full." % other_slot)
		var merged := mini(room, moved)
		_own(target, other_slot).amount += merged
		stack = _own(source, from_slot)
		stack.amount -= merged
		if stack.amount == 0:
			source[from_slot] = null
		return self

	if not whole:
		return _fail(Code.NOT_MERGEABLE, "Cannot drop part of a stack on a different item.")
	var other_definition := _definition(from, existing.item_id)
	if other_definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % existing.item_id)
	if not to._accepts(to_slot, stack, definition) or not from._accepts(from_slot, existing, other_definition):
		return _fail(Code.RULE_REJECTED, "Swap rejected by a slot rule.")
	if same:
		var after := to._occupancy(target, PackedInt32Array([from_slot, other_slot]))
		to._mark_area(after, to_slot, size)
		if not to._area_free(after, from_slot, to._size_of(existing)):
			return _fail_fit(Code.SLOT_OCCUPIED, "No room to swap '%s' and '%s'." % [stack.item_id, existing.item_id])
		target[other_slot] = null
		target[from_slot] = null
		target[to_slot] = stack
		target[from_slot] = existing
		return self
	var source_after := from._occupancy(source, PackedInt32Array([from_slot]))
	if not from._area_free(source_after, from_slot, from._size_of(existing)):
		return _fail_fit(Code.SLOT_OCCUPIED, "No room to swap '%s' and '%s'." % [stack.item_id, existing.item_id])
	target[other_slot] = null
	target[to_slot] = stack
	source[from_slot] = existing
	return self


func _split_grid(container: IKContainer, slots: Array, slot: int, amount: int, to_slot: int) -> IKTransaction:
	var stack: IKItemStack = slots[slot]
	var definition := _definition(container, stack.item_id)
	if definition == null:
		return _fail(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	var piece := _mark(stack.copy())
	piece.amount = amount
	var occupancy := container._occupancy(slots)
	if to_slot < 0:
		to_slot = container._find_spot(occupancy, piece, definition)
		if to_slot < 0:
			return _fail(Code.CONTAINER_FULL, "No empty slot to split into.")
	else:
		if not _check_slot(slots, to_slot):
			return self
		if not container._area_free(occupancy, to_slot, container._size_of(piece)):
			return _fail_fit(Code.SLOT_OCCUPIED, "No room for '%s' at cell %d." % [stack.item_id, to_slot])
		if not container._accepts(to_slot, piece, definition):
			return _fail(Code.RULE_REJECTED, "Slot %d does not accept '%s'." % [to_slot, stack.item_id])
	slots[to_slot] = piece
	_own(slots, slot).amount -= amount
	return self


func _place_grid(container: IKContainer, template: IKItemStack, definition: IKItemDefinition, allow_partial: bool) -> IKTransaction:
	var slots := _slots_of(container)
	var remaining := template.amount
	var single := definition.unique or template.has_uid()
	if template.has_uid() and template.amount != 1:
		return _fail(Code.INVALID_ARGUMENT, "A stack with a uid must have amount 1.")
	var max_stack := definition.get_effective_max_stack()
	if not single:
		var probe := IKItemStack.new(template.item_id, 1, "", template.data)
		for i in slots.size():
			if remaining == 0:
				break
			var existing: IKItemStack = slots[i]
			if existing != null and existing.can_merge_with(probe):
				var merged := mini(max_stack - existing.amount, remaining)
				if merged > 0:
					_own(slots, i).amount += merged
					remaining -= merged
	var occupancy := container._occupancy(slots)
	while remaining > 0:
		var piece: IKItemStack
		if single:
			piece = IKItemStack.new(template.item_id, 1, template.uid if template.has_uid() else IKUid.generate(), template.data)
		else:
			piece = IKItemStack.new(template.item_id, mini(max_stack, remaining), "", template.data)
		piece.rotated = template.rotated
		var spot := container._find_spot(occupancy, piece, definition)
		if spot < 0:
			break
		slots[spot] = _mark(piece)
		container._mark_area(occupancy, spot, container._size_of(piece))
		remaining -= piece.amount
	var placed := template.amount - remaining
	if placed == 0 or (remaining > 0 and not allow_partial):
		return _fail(Code.CONTAINER_FULL, "Only %d of %d '%s' fit." % [placed, template.amount, template.item_id])
	_add_delta(template.item_id, placed)
	_remainder += remaining
	return self


func _place(container: IKContainer, template: IKItemStack, definition: IKItemDefinition, allow_partial: bool) -> IKTransaction:
	if container.is_grid():
		return _place_grid(container, template, definition, allow_partial)
	var slots := _slots_of(container)
	var remaining := template.amount
	if definition.unique or template.has_uid():
		if template.has_uid() and template.amount != 1:
			return _fail(Code.INVALID_ARGUMENT, "A stack with a uid must have amount 1.")
		for i in slots.size():
			if remaining == 0:
				break
			if slots[i] != null:
				continue
			var uid := template.uid if template.has_uid() else IKUid.generate()
			var single := _mark(IKItemStack.new(template.item_id, 1, uid, template.data))
			if container._accepts(i, single, definition):
				slots[i] = single
				remaining -= 1
	else:
		var max_stack := definition.get_effective_max_stack()
		var probe := IKItemStack.new(template.item_id, 1, "", template.data)
		for i in slots.size():
			if remaining == 0:
				break
			var existing: IKItemStack = slots[i]
			if existing != null and existing.can_merge_with(probe):
				var merged := mini(max_stack - existing.amount, remaining)
				if merged > 0:
					_own(slots, i).amount += merged
					remaining -= merged
		for i in slots.size():
			if remaining == 0:
				break
			if slots[i] != null or not container._accepts(i, probe, definition):
				continue
			var placed_here := mini(max_stack, remaining)
			slots[i] = _mark(IKItemStack.new(template.item_id, placed_here, "", template.data))
			remaining -= placed_here
	var placed := template.amount - remaining
	if placed == 0 or (remaining > 0 and not allow_partial):
		return _fail(Code.CONTAINER_FULL, "Only %d of %d '%s' fit." % [placed, template.amount, template.item_id])
	_add_delta(template.item_id, placed)
	_remainder += remaining
	return self


func _validate_stack(container: IKContainer, slot: int, stack: IKItemStack) -> IKResult:
	var definition := _definition(container, stack.item_id)
	if definition == null:
		return IKResult.failure(Code.UNKNOWN_ITEM, "Unknown item '%s'." % stack.item_id)
	if stack.amount < 1 or stack.amount > definition.get_effective_max_stack():
		return IKResult.failure(Code.INVARIANT_VIOLATION,
			"Slot %d holds %d '%s' (max %d)." % [slot, stack.amount, stack.item_id, definition.get_effective_max_stack()])
	if definition.unique and not stack.has_uid():
		return IKResult.failure(Code.INVARIANT_VIOLATION, "Unique item '%s' has no uid." % stack.item_id)
	if not container._accepts(slot, stack, definition):
		return IKResult.failure(Code.RULE_REJECTED, "Slot %d does not accept '%s'." % [slot, stack.item_id])
	return null
