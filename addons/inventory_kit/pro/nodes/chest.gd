class_name IKChest
extends IKInventory
## A container placed in the world (chest, crate, corpse...). Tracks whether it is
## open and offers "take all". Give each chest a unique [member container_id] so
## it is saved separately.

signal opened
signal closed

var is_open := false


func _init() -> void:
	container_id = &"chest"
	size = 12


func open() -> void:
	if not is_open:
		is_open = true
		opened.emit()


func close() -> void:
	if is_open:
		is_open = false
		closed.emit()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func is_empty() -> bool:
	return container.get_free_slot_count() == container.size()


## Moves everything that fits into [param destination]. What does not fit stays
## in the chest and is reported in [member IKResult.remainder].
func take_all(destination: IKContainer) -> IKResult:
	var left := 0
	var moved_any := false
	for i in container.size():
		var stack := container.get_stack(i)
		if stack == null or container.get_definition(i) == null:
			if stack != null:
				left += stack.amount
			continue
		var result := container.transfer_to(i, destination)
		if result.ok:
			moved_any = true
			left += result.remainder
		else:
			left += stack.amount
	if not moved_any and left > 0:
		return IKResult.failure(IKResult.Code.CONTAINER_FULL, "No room to take anything.")
	return IKResult.success(left)
