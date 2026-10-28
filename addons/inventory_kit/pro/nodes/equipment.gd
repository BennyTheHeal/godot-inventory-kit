class_name IKEquipment
extends IKInventory
## Equipment slots: one slot per entry of [member slot_types], each accepting only
## items whose [member IKItemDefinition.equip_slot] matches.
## [codeblock]
## equipment.equip_from(bag.container, 3)
## var armor := equipment.sum_property(&"armor")  # set bonuses included
## [/codeblock]

signal equipped(slot_type: StringName, stack: IKItemStack)
signal unequipped(slot_type: StringName, stack: IKItemStack)
## A set bonus started or stopped applying.
signal set_bonus_changed(bonus: IKSetBonus, active: bool)

## Slot types in display order. Repeat a type for several slots (two rings).
@export var slot_types: Array[StringName] = [&"head", &"body", &"weapon", &"offhand"]:
	set(value):
		slot_types = value
		size = value.size()
## Bonuses for wearing several pieces of a set (items with properties["set"]).
@export var set_bonuses: IKSetBonusList:
	set(value):
		set_bonuses = value
		if _container != null:
			_update_set_bonuses()
## Entry of IKItemDefinition.properties naming the set an item belongs to.
@export var set_property: StringName = &"set"

var _last: Array = []
var _active_bonuses: Array[IKSetBonus] = []


func _init() -> void:
	container_id = &"equipment"
	size = slot_types.size()


## Copy of what is worn in the first slot of [param slot_type], or null.
func get_equipped(slot_type: StringName) -> IKItemStack:
	var index := slot_types.find(slot_type)
	return container.get_stack(index) if index >= 0 else null


## Moves an item from [param source] into a matching slot (first empty one, else
## swaps with the first matching slot).
func equip_from(source: IKContainer, slot: int) -> IKResult:
	var definition := source.get_definition(slot)
	if definition == null or definition.equip_slot == &"":
		return IKResult.failure(IKResult.Code.RULE_REJECTED, "This item cannot be equipped.")
	var target := -1
	for i in slot_types.size():
		if slot_types[i] != definition.equip_slot:
			continue
		if container.is_slot_empty(i):
			target = i
			break
		if target < 0:
			target = i
	if target < 0:
		return IKResult.failure(IKResult.Code.RULE_REJECTED, "No '%s' slot." % definition.equip_slot)
	return source.move_to(slot, container, target)


## Moves the item worn in [param slot_type] into [param destination].
func unequip(slot_type: StringName, destination: IKContainer) -> IKResult:
	var index := slot_types.find(slot_type)
	if index < 0 or container.is_slot_empty(index):
		return IKResult.failure(IKResult.Code.SLOT_EMPTY, "Nothing equipped there.")
	var result := container.transfer_to(index, destination)
	if result.ok and result.remainder > 0:
		return IKResult.failure(IKResult.Code.CONTAINER_FULL, "No room to unequip.")
	return result


## Sum of a numeric [member IKItemDefinition.properties] entry over everything worn,
## plus the active set bonuses unless [param include_set_bonuses] is false.
func sum_property(property: StringName, include_set_bonuses: bool = true) -> float:
	var total := 0.0
	for i in container.size():
		var definition := container.get_definition(i)
		if definition != null:
			total += float(definition.properties.get(property, 0.0))
	if include_set_bonuses:
		for bonus in _active_bonuses:
			total += float(bonus.properties.get(property, 0.0))
	return total


## Number of worn pieces belonging to [param set_id].
func count_set_pieces(set_id: StringName) -> int:
	var total := 0
	for i in container.size():
		var definition := container.get_definition(i)
		if definition != null and StringName(str(definition.properties.get(set_property, ""))) == set_id:
			total += 1
	return total


## Set bonuses currently applying.
func get_active_set_bonuses() -> Array[IKSetBonus]:
	return _active_bonuses.duplicate()


func is_set_bonus_active(bonus: IKSetBonus) -> bool:
	return _active_bonuses.has(bonus)


## Recomputes the active set bonuses. Called automatically when the equipment
## changes; call it after swapping the container's database.
func refresh_set_bonuses() -> void:
	_update_set_bonuses()


func _configure_container(new_container: IKContainer) -> void:
	for i in slot_types.size():
		new_container.set_slot_rule(i, IKEquipSlotRule.new(slot_types[i]))
	_last.resize(new_container.size())
	new_container.slots_changed.connect(_on_slots_changed)


func _update_set_bonuses() -> void:
	var now: Array[IKSetBonus] = []
	if set_bonuses != null:
		for bonus in set_bonuses.bonuses:
			if bonus != null and count_set_pieces(bonus.set_id) >= bonus.pieces_required:
				now.append(bonus)
	var before := _active_bonuses
	_active_bonuses = now
	for bonus in before:
		if not now.has(bonus):
			set_bonus_changed.emit(bonus, false)
	for bonus in now:
		if not before.has(bonus):
			set_bonus_changed.emit(bonus, true)


func _on_slots_changed(slot_indices: PackedInt32Array) -> void:
	_update_set_bonuses()
	for i in slot_indices:
		if i >= slot_types.size():
			continue
		var now := container.get_stack(i)
		var before: IKItemStack = _last[i]
		if IKItemStack.same(before, now):
			continue
		_last[i] = now
		if before != null:
			unequipped.emit(slot_types[i], before)
		if now != null:
			equipped.emit(slot_types[i], now)
