class_name IKCursor
extends RefCounted
## The stack "in hand" while the player moves items around.
##
## Held items live in a real one-slot container, so they are counted by every
## transaction check and can be saved like any other container: they are never
## "in the air". Input-agnostic: mouse, gamepad and touch all call the same
## methods ([method primary], [method secondary], [method quick_move]).
##
## Grid containers: picking works on any cell of an item, placing puts the held
## item's top-left corner on the given cell, and [method rotate_held] turns it.

const Code := IKResult.Code

## One-slot container holding the stack in hand. Connect to its
## [signal IKContainer.changed] signal to react when the hand changes.
var container: IKContainer
## Where the held stack came from, used by [method return_held].
var origin_container: IKContainer
var origin_slot := -1


func _init(database: IKItemDatabase = null) -> void:
	container = IKContainer.new(&"cursor", 1, database)


func is_holding() -> bool:
	return not container.is_slot_empty(0)


## Copy of the held stack, or null.
func get_held() -> IKItemStack:
	return container.get_stack(0)


## Takes [param amount] (-1 = all) from a slot into the empty hand.
func pick(from: IKContainer, slot: int, amount: int = -1) -> IKResult:
	if is_holding():
		return IKResult.failure(Code.SLOT_OCCUPIED, "Already holding items.")
	slot = _anchor(from, slot)
	var result := from.move_to(slot, container, 0, amount)
	if result.ok and is_holding():
		origin_container = from
		origin_slot = slot
	return result


## Puts [param amount] (-1 = all) of the held stack into a slot: place, merge, or
## swap with a different item (the hand then holds the item that was there).
func place(to: IKContainer, slot: int, amount: int = -1) -> IKResult:
	if not is_holding():
		return IKResult.failure(Code.SLOT_EMPTY, "Nothing held.")
	var swapped_slot := slot
	var swapping := false
	if to.is_grid():
		var under := to.get_overlapping(slot, get_held())
		if under.size() == 1:
			swapped_slot = under[0]
			swapping = not _mergeable(to, swapped_slot)
	else:
		swapping = not to.is_slot_empty(slot) and not _mergeable(to, slot)
	var result := container.move_to(0, to, slot, amount)
	if result.ok:
		if not is_holding():
			_clear_origin()
		elif swapping:
			origin_container = to
			origin_slot = swapped_slot
	return result


## Main action (left click, A button): pick the whole stack, or place everything held.
func primary(target: IKContainer, slot: int) -> IKResult:
	if is_holding():
		return place(target, slot)
	if target.is_slot_empty(slot):
		return IKResult.success()
	return pick(target, slot)


## Secondary action (right click, X button): pick half the stack, or place one item.
func secondary(target: IKContainer, slot: int) -> IKResult:
	if is_holding():
		return place(target, slot, 1)
	var stack := target.get_stack(_anchor(target, slot))
	if stack == null:
		return IKResult.success()
	return pick(target, slot, ceili(stack.amount / 2.0))


## Sends a whole slot to another container (shift-click). Only with an empty hand.
func quick_move(from: IKContainer, slot: int, to: IKContainer) -> IKResult:
	if is_holding():
		return IKResult.failure(Code.SLOT_OCCUPIED, "Put the held items down first.")
	if from.is_slot_empty(slot):
		return IKResult.success()
	return from.transfer_to(_anchor(from, slot), to)


## Turns the held item a quarter turn (grid inventories: R key, middle click...).
func rotate_held() -> IKResult:
	if not is_holding():
		return IKResult.failure(Code.SLOT_EMPTY, "Nothing held.")
	return container.rotate(0)


## Puts the held stack back: its origin slot first, then anywhere in the origin
## container, then in [param fallbacks]. Fails with CONTAINER_FULL if some items
## still have nowhere to go; they stay in the hand (see [method take_held]).
func return_held(fallbacks: Array = []) -> IKResult:
	if not is_holding():
		return IKResult.success()
	if origin_container != null and origin_container.is_valid_slot(origin_slot) and _fits_back():
		container.move_to(0, origin_container, origin_slot)
	var targets: Array = []
	if origin_container != null:
		targets.append(origin_container)
	targets.append_array(fallbacks)
	for target: IKContainer in targets:
		if not is_holding():
			break
		if target != null and target != container:
			container.transfer_to(0, target)
	if is_holding():
		return IKResult.failure(Code.CONTAINER_FULL, "No room to put the held items back.")
	_clear_origin()
	return IKResult.success()


## Removes the held stack from the inventory and returns it, e.g. to drop it in
## the world. From then on the game is responsible for it.
func take_held() -> IKItemStack:
	var stack := get_held()
	if stack != null:
		container.remove_at(0)
		_clear_origin()
	return stack


func _fits_back() -> bool:
	if origin_container.is_grid():
		var held := get_held()
		if origin_container.can_place(origin_slot, held):
			return true
		var under := origin_container.get_overlapping(origin_slot, held)
		return under.size() == 1 and _mergeable(origin_container, under[0]) \
			and origin_container._in_bounds(origin_slot, origin_container.get_size_of(held))
	return origin_container.is_slot_empty(origin_slot) or _mergeable(origin_container, origin_slot)


## Grid containers: the top-left cell of the item covering [param slot].
func _anchor(target: IKContainer, slot: int) -> int:
	if target != null and target.is_grid():
		var anchor := target.get_anchor(slot)
		if anchor >= 0:
			return anchor
	return slot


func _mergeable(target: IKContainer, slot: int) -> bool:
	var existing := target.get_stack(_anchor(target, slot))
	var held := get_held()
	return existing != null and held != null and existing.can_merge_with(held)


func _clear_origin() -> void:
	origin_container = null
	origin_slot = -1
