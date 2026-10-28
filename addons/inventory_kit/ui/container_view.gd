class_name IKContainerView
extends GridContainer
## Grid of [IKSlotView]s showing one container. Updates itself when the
## container changes.
##
## Place it inside an [IKInventoryUI] to make it interactive; on its own it is
## a read-only display. Set [member inventory] in the inspector, or call [method bind].
##
## Grid containers ([method IKContainer.is_grid]) get one view per cell and as many
## columns as the grid ([member columns] is set for you). Items are drawn over
## every cell they cover and the held item shows where it would land (green: fits,
## red: does not fit).

## Node owning the container to display (alternative to [method bind]).
@export var inventory: IKInventory
## Shift-click sends items to this view's container.
@export var quick_move_target: IKContainerView
## Overrides the skin of the parent IKInventoryUI.
@export var skin: IKSkin
## Placeholder icons for empty slots, by slot index (e.g. equipment outlines).
@export var empty_icons: Array[Texture2D] = []

## Emitted for every slot view created (also after a rebuild), to customize it.
signal slot_view_created(slot_view: IKSlotView)

var container: IKContainer
## Optional Callable(stack: IKItemStack, definition: IKItemDefinition) -> bool.
## Occupied slots that do not match are dimmed. Set an invalid Callable to clear.
var filter: Callable:
	set(value):
		filter = value
		_apply_filter()

var _views: Array[IKSlotView] = []
var _ui: IKInventoryUI
# Grid highlight state (see update_grid_highlight).
var _hover_slot := -1
var _active_slot := -1
var _focus_active := false
var _preview := {}
var _preview_ok := false


func _enter_tree() -> void:
	var node := get_parent()
	while node != null and not node is IKInventoryUI:
		node = node.get_parent()
	_ui = node as IKInventoryUI
	if _ui != null:
		_ui._register_view(self)
	# Views built before entering the screen: give them its cursor and skin.
	for view in _views:
		view.setup(container, view.slot, get_skin(), _ui.cursor if _ui != null else null)


func _exit_tree() -> void:
	if _ui != null:
		_ui._unregister_view(self)
		_ui = null


func _ready() -> void:
	if container == null and inventory != null:
		bind(inventory.container)


func bind(p_container: IKContainer) -> void:
	if container != null and container.slots_changed.is_connected(_on_slots_changed):
		container.slots_changed.disconnect(_on_slots_changed)
	container = p_container
	if container != null:
		container.slots_changed.connect(_on_slots_changed)
		if _ui != null:
			_ui._on_view_bound(self)
	_rebuild()


func get_slot_views() -> Array[IKSlotView]:
	return _views


func get_slot_view(slot: int) -> IKSlotView:
	return _views[slot] if slot >= 0 and slot < _views.size() else null


func get_skin() -> IKSkin:
	if skin != null:
		return skin
	if _ui != null:
		return _ui.get_skin()
	return IKSkin.create_default()


func refresh_all() -> void:
	for view in _views:
		view.refresh()
	_apply_filter()
	update_grid_highlight()


func is_grid() -> bool:
	return container != null and container.is_grid()


# --- Grid highlight -----------------------------------------------------------

## Grid: the cell under the keyboard/gamepad selection, else under the mouse (-1: none).
func get_active_slot() -> int:
	return _active_slot


## Grid: true when the active cell comes from the keyboard/gamepad selection.
func is_focus_active() -> bool:
	return _focus_active


## Grid: cells the held item would cover at the active cell (cell -> true).
func get_preview_cells() -> Dictionary:
	return _preview


## Grid: true if the held item can be dropped at the active cell (place, merge or swap).
func is_preview_valid() -> bool:
	return _preview_ok


## Recomputes the hovered item and the drop preview of a grid view, then redraws.
## Called automatically on hover, focus, cursor and container changes.
func update_grid_highlight() -> void:
	if not is_grid():
		for view in _views:
			view.queue_redraw()
		return
	var focused_slot := -1
	for view in _views:
		if view.focused:
			focused_slot = view.slot
			break
	_focus_active = focused_slot >= 0
	_active_slot = focused_slot
	if _active_slot < 0 and _hover_slot >= 0:
		var hovered := get_slot_view(_hover_slot)
		if hovered != null and hovered.hover_enabled:
			_active_slot = _hover_slot
	_preview = {}
	_preview_ok = false
	var cursor := _ui.cursor if _ui != null else null
	if cursor != null and cursor.is_holding() and _active_slot >= 0:
		var held := cursor.get_held()
		for cell in container._area(_active_slot, container.get_size_of(held)):
			_preview[cell] = true
		_preview_ok = container.can_drop(_active_slot, held)
	for view in _views:
		view.queue_redraw()


func _on_cell_hovered(view: IKSlotView, hovered: bool) -> void:
	if hovered:
		_hover_slot = view.slot
	elif _hover_slot == view.slot:
		_hover_slot = -1
	update_grid_highlight()


func _apply_filter() -> void:
	for view in _views:
		var stack := view.get_item_stack()
		var anchor := view.get_anchor_slot()
		view.dimmed = filter.is_valid() and stack != null \
			and not filter.call(stack, container.get_definition(anchor))


func _rebuild() -> void:
	for view in _views:
		remove_child(view)
		view.queue_free()
	_views.clear()
	_hover_slot = -1
	_active_slot = -1
	_preview = {}
	if container == null:
		return
	if container.is_grid():
		columns = container.get_grid_width()
	var current_skin := get_skin()
	add_theme_constant_override(&"h_separation", current_skin.slot_separation)
	add_theme_constant_override(&"v_separation", current_skin.slot_separation)
	var cursor := _ui.cursor if _ui != null else null
	for i in container.size():
		var view := IKSlotView.new()
		view.name = "Slot%d" % i
		view.owner_view = self
		if i < empty_icons.size():
			view.empty_icon = empty_icons[i]
		add_child(view)
		view.setup(container, i, current_skin, cursor)
		view.pressed.connect(_on_slot_pressed)
		view.released.connect(_on_slot_released)
		_views.append(view)
		slot_view_created.emit(view)
	_apply_filter()


func _on_slots_changed(slot_indices: PackedInt32Array) -> void:
	if container.size() != _views.size():
		_rebuild()
		return
	if container.is_grid():
		# Moving one item changes which cells are covered: refresh every cell.
		for view in _views:
			view.refresh()
		_apply_filter()
		update_grid_highlight()
		return
	for i in slot_indices:
		_views[i].refresh()
	if filter.is_valid():
		_apply_filter()


func _on_slot_pressed(view: IKSlotView, event: InputEventMouseButton) -> void:
	if _ui != null:
		_ui._handle_press(self, view, event)


func _on_slot_released(view: IKSlotView, event: InputEventMouseButton) -> void:
	if _ui != null:
		_ui._handle_release(view, event)
