class_name IKItemStack
extends RefCounted
## A quantity of one item type in a slot.
##
## Stacks returned by [IKContainer] are copies: editing them never changes the
## inventory. Use [IKTransaction] (or the container helpers) to make changes.

var item_id: StringName
var amount: int = 1
## Instance id for unique items; empty for regular stackable items.
var uid: String = ""
## Per-copy data. Keep values JSON-compatible (bool, int, float, String, Array, Dictionary).
var data: Dictionary = {}
## Turned a quarter turn in a grid container (see [method IKItemDefinition.get_grid_size]).
## Kept when the stack moves; containers with classic slots ignore it.
var rotated := false


func _init(p_item_id: StringName = &"", p_amount: int = 1, p_uid: String = "", p_data: Dictionary = {}) -> void:
	item_id = p_item_id
	amount = p_amount
	uid = p_uid
	data = p_data.duplicate(true)


func copy() -> IKItemStack:
	var result := IKItemStack.new(item_id, amount, uid, data)
	result.rotated = rotated
	return result


func has_uid() -> bool:
	return not uid.is_empty()


## True if both stacks can share a slot: same item, no uid, identical data
## (rotation does not matter: the merged stack keeps the target's).
func can_merge_with(other: IKItemStack) -> bool:
	return other != null \
		and other.item_id == item_id \
		and not has_uid() \
		and not other.has_uid() \
		and data == other.data


func to_debug_dict() -> Dictionary:
	var result := {"id": item_id, "n": amount, "uid": uid, "data": data.duplicate(true)}
	if rotated:
		result["rot"] = true
	return result


## Value equality, null-safe.
static func same(a: IKItemStack, b: IKItemStack) -> bool:
	if a == null or b == null:
		return a == b
	return a.item_id == b.item_id and a.amount == b.amount and a.uid == b.uid and a.data == b.data \
		and a.rotated == b.rotated


func _to_string() -> String:
	if has_uid():
		return "%s x%d [%s]" % [item_id, amount, uid.substr(0, 8)]
	return "%s x%d" % [item_id, amount]
