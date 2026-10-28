class_name IKHotbar
extends IKInventory
## Quick-access bar: a small container with one selected slot.
##
## Keys 1-9 select a slot, the mouse wheel cycles, and [code]ik_hotbar_use[/code]
## (gamepad right trigger by default) uses the selected item through [IKItemUser].
## Assign [member view] to highlight the selection.

signal selection_changed(index: int)
signal item_used(stack: IKItemStack)

## View showing this hotbar; its selected slot is highlighted.
@export var view: IKContainerView:
	set(value):
		if view != null and view.slot_view_created.is_connected(_on_slot_view_created):
			view.slot_view_created.disconnect(_on_slot_view_created)
		view = value
		if view != null:
			view.slot_view_created.connect(_on_slot_view_created)
		_update_marks()
## Passed to item effects as [member IKUseContext.user] (usually the player).
@export var user: Node
## Read hotbar actions in _unhandled_input().
@export var handle_input := true

var selected := 0


func _init() -> void:
	container_id = &"hotbar"
	size = 8


func _ready() -> void:
	super._ready()
	IKInputActions.ensure_defaults()
	_update_marks()


func select(index: int) -> void:
	if size <= 0:
		return
	var wrapped := posmod(index, size)
	if wrapped == selected:
		return
	selected = wrapped
	_update_marks()
	selection_changed.emit(selected)


func select_next() -> void:
	select(selected + 1)


func select_previous() -> void:
	select(selected - 1)


func get_selected_stack() -> IKItemStack:
	return container.get_stack(selected)


func use_selected() -> IKResult:
	var stack := get_selected_stack()
	var result := IKItemUser.use(container, selected, user)
	if result.ok:
		item_used.emit(stack)
	return result


func _unhandled_input(event: InputEvent) -> void:
	if not handle_input:
		return
	for i in mini(size, IKInputActions.HOTBAR_SLOTS.size()):
		if event.is_action_pressed(IKInputActions.HOTBAR_SLOTS[i]):
			select(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(IKInputActions.HOTBAR_NEXT):
		select_next()
	elif event.is_action_pressed(IKInputActions.HOTBAR_PREVIOUS):
		select_previous()
	elif event.is_action_pressed(IKInputActions.HOTBAR_USE):
		use_selected()
	else:
		return
	get_viewport().set_input_as_handled()


func _update_marks() -> void:
	if view == null:
		return
	for slot_view in view.get_slot_views():
		slot_view.marked = slot_view.slot == selected


func _on_slot_view_created(slot_view: IKSlotView) -> void:
	slot_view.marked = slot_view.slot == selected
