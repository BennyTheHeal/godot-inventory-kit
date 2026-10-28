class_name IKInputController
extends Node
## Keyboard, gamepad and touch control for the [IKInventoryUI] this node is a child of.
##
## Add it as a child of your IKInventoryUI; nothing else to configure.
## - Keyboard / gamepad: move a selection between slots (and between containers,
##   following the screen layout), then use the same actions as the mouse.
##   See [IKInputActions] for the default bindings.
## - Touch: tap to pick up / put down, drag to move, long press for half / one.
## - Grid inventories: the selection jumps over the cells of the item it is on,
##   and Rotate (T, left stick press, a second finger tap) turns the held item.
## - The last device used wins: moving the mouse hides the selection, pressing a
##   key or button shows it again where it was. A mouse click moves the selection
##   to the clicked slot, so switching devices never loses your place.

signal input_mode_changed(mode: Mode)
## Cancel was pressed with an empty hand: close the inventory if you want.
signal close_requested
signal focus_changed(view: IKContainerView, slot: int)
## A usable item was used (U, gamepad Back/Select, or mouse double click).
signal item_used(definition: IKUsableItem, stack: IKItemStack)

enum Mode { MOUSE, FOCUS, TOUCH }

const Actions := preload("res://addons/inventory_kit/pro/input/input_actions.gd")

@export var enabled := true
## Start with the selection visible (console builds, gamepad-only games).
@export var start_in_focus_mode := false
## Seconds before a held direction starts repeating, then between repeats.
@export var repeat_delay := 0.35
@export var repeat_interval := 0.09
## Handle taps and long presses directly (turns off the UI's emulated-mouse handling).
@export var handle_touch := true
@export var long_press_time := 0.45
@export var touch_drag_threshold := 12.0
## Passed to item effects as the user (usually the player node).
@export var use_target: Node
## "Use" on an equippable item equips it here (or unequips it if already worn).
@export var equipment: IKEquipment
## Mouse double click uses / equips the item.
@export var use_on_double_click := true

var mode: Mode = Mode.MOUSE
var ui: IKInventoryUI
var focused_view: IKContainerView
var focused_slot := -1

var _held_direction := Vector2i.ZERO
var _repeat_timer := 0.0
var _last_slot := {}  # view instance id -> slot index
var _touch := _Touch.new()


class _Touch:
	var active := false
	var start := Vector2.ZERO
	var slot_view: IKSlotView
	var time := 0.0
	var moved := false
	var long_fired := false
	var dragging := false


func _ready() -> void:
	Actions.ensure_defaults()
	ui = get_parent() as IKInventoryUI
	if ui == null:
		push_error("IKInputController must be a child of an IKInventoryUI.")
		set_process(false)
		set_process_input(false)
		return
	ui.slot_pressed.connect(_on_slot_pressed)
	ui.visibility_changed.connect(_on_ui_visibility_changed)
	if handle_touch:
		ui.accept_emulated_mouse = false
	if start_in_focus_mode:
		set_mode.call_deferred(Mode.FOCUS)


func is_active() -> bool:
	return enabled and ui != null and ui.is_visible_in_tree()


func set_mode(new_mode: Mode) -> void:
	if mode == new_mode:
		if new_mode == Mode.FOCUS:
			_ensure_focus()
		return
	mode = new_mode
	if mode == Mode.FOCUS:
		if is_inside_tree():
			get_viewport().gui_release_focus()
		_ensure_focus()
	_apply_focus_visual()
	input_mode_changed.emit(mode)


## Selects a slot (visible in FOCUS mode).
func focus_slot(view: IKContainerView, slot: int) -> void:
	var previous := get_focused_slot_view()
	if previous != null:
		previous.focused = false
	focused_view = view
	focused_slot = slot
	if view != null:
		_last_slot[view.get_instance_id()] = slot
	_apply_focus_visual()
	focus_changed.emit(view, slot)


func get_focused_slot_view() -> IKSlotView:
	if focused_view == null or not is_instance_valid(focused_view):
		return null
	return focused_view.get_slot_view(focused_slot)


## Moves the selection one step. [param direction] is one of Vector2i.LEFT/RIGHT/UP/DOWN.
func move_focus(direction: Vector2i) -> void:
	_ensure_focus()
	if focused_view == null:
		return
	if focused_view.is_grid():
		var cell := _grid_step(focused_view, focused_slot, direction)
		if cell >= 0:
			focus_slot(focused_view, cell)
			return
		var outside := _find_neighbor(direction)
		if not outside.is_empty():
			focus_slot(outside[0], outside[1])
		return
	var count := focused_view.get_slot_views().size()
	var columns := maxi(1, focused_view.columns)
	var column := focused_slot % columns
	var target := -1
	match direction:
		Vector2i.LEFT:
			if column > 0:
				target = focused_slot - 1
		Vector2i.RIGHT:
			if column < columns - 1 and focused_slot + 1 < count:
				target = focused_slot + 1
		Vector2i.UP:
			if focused_slot - columns >= 0:
				target = focused_slot - columns
		Vector2i.DOWN:
			if focused_slot + columns < count:
				target = focused_slot + columns
			elif focused_slot / columns < (count - 1) / columns:
				target = count - 1  # shorter last row
	if target >= 0:
		focus_slot(focused_view, target)
		return
	var neighbor := _find_neighbor(direction)
	if not neighbor.is_empty():
		focus_slot(neighbor[0], neighbor[1])


## Next cell of a grid view in [param direction], or -1 at the edge. With an empty
## hand, cells of the item the selection is on are skipped (one press = next item).
func _grid_step(view: IKContainerView, from_slot: int, direction: Vector2i) -> int:
	var container := view.container
	var start := container.get_anchor(from_slot)
	var skip := start >= 0 and not ui.cursor.is_holding()
	var cell := container.cell_of(from_slot) + direction
	var slot := container.slot_of(cell)
	while slot >= 0 and skip and container.get_anchor(slot) == start:
		cell += direction
		slot = container.slot_of(cell)
	return slot


## Jumps to the next (+1) or previous (-1) container view, at its last selected slot.
func cycle_panel(step: int) -> void:
	var views := _visible_views()
	if views.is_empty():
		return
	var index := views.find(focused_view)
	var next: IKContainerView = views[posmod(index + step, views.size())] if index >= 0 else views[0]
	focus_slot(next, clampi(_last_slot.get(next.get_instance_id(), 0), 0, next.get_slot_views().size() - 1))


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if handle_touch and _handle_touch(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.relative.length() > 1.0:
			set_mode(Mode.MOUSE)
		return
	if event is InputEventMouseButton:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			set_mode(Mode.MOUSE)
		return
	if _handle_action(event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_active():
		return
	if _held_direction != Vector2i.ZERO:
		if not Input.is_action_pressed(_action_for(_held_direction)):
			_held_direction = Vector2i.ZERO
		else:
			_repeat_timer -= delta
			if _repeat_timer <= 0.0:
				_repeat_timer = repeat_interval
				move_focus(_held_direction)
	if _touch.active and not _touch.moved and not _touch.long_fired and _touch.slot_view != null:
		_touch.time += delta
		if _touch.time >= long_press_time:
			_touch.long_fired = true
			_run(ui.cursor.secondary(_touch.slot_view.container, _touch.slot_view.slot))
	# Views rebuild their slots when a container is resized: keep the highlight.
	if mode == Mode.FOCUS:
		var slot_view := get_focused_slot_view()
		if slot_view != null and not slot_view.focused:
			_apply_focus_visual()


func _handle_action(event: InputEvent) -> bool:
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var action := _action_for(direction)
		if not event.is_action(action):
			continue
		if event.is_action_pressed(action, false):
			if mode != Mode.FOCUS:
				set_mode(Mode.FOCUS)  # the first press only shows the selection
			else:
				move_focus(direction)
			_held_direction = direction
			_repeat_timer = repeat_delay
		elif event.is_action_released(action) and _held_direction == direction:
			_held_direction = Vector2i.ZERO
		return true
	if event.is_action_pressed(Actions.ROTATE):
		if not ui.cursor.is_holding():
			return false
		ui.rotate_held()
		return true
	if event.is_action_pressed(Actions.CANCEL):
		if ui.cursor.is_holding():
			ui.return_held()
		else:
			close_requested.emit()
		return true
	for action in [Actions.PRIMARY, Actions.SECONDARY, Actions.QUICK_MOVE, Actions.PREVIOUS_PANEL,
			Actions.NEXT_PANEL, Actions.USE, Actions.SORT]:
		if not event.is_action_pressed(action):
			continue
		if mode != Mode.FOCUS:
			set_mode(Mode.FOCUS)
			return true
		match action:
			Actions.PREVIOUS_PANEL:
				cycle_panel(-1)
			Actions.NEXT_PANEL:
				cycle_panel(1)
			_:
				_run_on_focus(action)
		return true
	return false


func _run_on_focus(action: StringName) -> void:
	var slot_view := get_focused_slot_view()
	if slot_view == null:
		return
	var cursor := ui.cursor
	match action:
		Actions.PRIMARY:
			_run(cursor.primary(slot_view.container, slot_view.slot))
		Actions.SECONDARY:
			_run(cursor.secondary(slot_view.container, slot_view.slot))
		Actions.QUICK_MOVE:
			var target := focused_view.quick_move_target
			if target != null and target.container != null:
				_run(cursor.quick_move(slot_view.container, slot_view.slot, target.container))
		Actions.USE:
			if not cursor.is_holding():
				_run(use_slot(focused_view, slot_view.slot))
		Actions.SORT:
			if not cursor.is_holding():
				_run(IKSorter.sort(focused_view.container))


## Uses a usable item, or equips / unequips an equippable one (see [member equipment]).
func use_slot(view: IKContainerView, slot: int) -> IKResult:
	var container := view.container
	if container.is_grid() and container.get_anchor(slot) >= 0:
		slot = container.get_anchor(slot)
	var definition := container.get_definition(slot)
	var stack := container.get_stack(slot)
	if definition is IKUsableItem:
		var result := IKItemUser.use(container, slot, use_target)
		if result.ok:
			item_used.emit(definition, stack)
		return result
	if definition != null and definition.equip_slot != &"" and equipment != null:
		if container == equipment.container:
			var destination := _unequip_destination(view)
			if destination == null:
				return IKResult.failure(IKResult.Code.CONTAINER_FULL, "Nowhere to put it.")
			return container.transfer_to(slot, destination)
		return equipment.equip_from(container, slot)
	return IKResult.failure(IKResult.Code.NOT_USABLE, "This item cannot be used.")


func _unequip_destination(view: IKContainerView) -> IKContainer:
	if view.quick_move_target != null and view.quick_move_target.container != null:
		return view.quick_move_target.container
	for other in _visible_views():
		if other != view and other.container != null and other.container != equipment.container:
			return other.container
	return null


func _handle_touch(event: InputEvent) -> bool:
	if event.index != 0:
		# A second finger tapping while an item is held turns it (grid inventories).
		if event is InputEventScreenTouch and event.pressed and event.index == 1 and ui.cursor.is_holding():
			ui.rotate_held()
			return true
		return false
	if event is InputEventScreenTouch:
		if event.pressed:
			set_mode(Mode.TOUCH)
			_touch = _Touch.new()
			_touch.active = true
			_touch.start = event.position
			_touch.slot_view = ui.find_slot_view_at(event.position)
			_set_cursor_anchor(_touch.slot_view)
			return _touch.slot_view != null
		if not _touch.active:
			return false
		var touch := _touch
		_touch = _Touch.new()
		if touch.long_fired:
			return true
		if touch.dragging:
			var target := ui.find_slot_view_at(event.position)
			if target != null:
				_run(ui.cursor.primary(target.container, target.slot))
			return true
		if touch.slot_view != null and not touch.moved:
			_run(ui.cursor.primary(touch.slot_view.container, touch.slot_view.slot))
			return true
		return false
	# InputEventScreenDrag
	if not _touch.active:
		return false
	if not _touch.moved and event.position.distance_to(_touch.start) > touch_drag_threshold:
		_touch.moved = true
		var origin := _touch.slot_view
		if origin != null and not ui.cursor.is_holding() and not origin.container.is_slot_empty(origin.slot):
			_run(ui.cursor.primary(origin.container, origin.slot))
			_touch.dragging = ui.cursor.is_holding()
	if _touch.dragging:
		var under := ui.find_slot_view_at(event.position)
		if under != null:
			_set_cursor_anchor(under)
	return _touch.slot_view != null


func _run(result: IKResult) -> void:
	ui.report_result(result)


func _ensure_focus() -> void:
	if focused_view != null and is_instance_valid(focused_view) and focused_view.is_visible_in_tree() \
			and ui.get_container_views().has(focused_view) and focused_view.get_slot_view(focused_slot) != null:
		return
	var views := _visible_views()
	if views.is_empty():
		focused_view = null
		focused_slot = -1
		return
	var view: IKContainerView = views[0]
	focus_slot(view, clampi(_last_slot.get(view.get_instance_id(), 0), 0, maxi(0, view.get_slot_views().size() - 1)))


func _apply_focus_visual() -> void:
	ui.set_hover_enabled(mode == Mode.MOUSE)
	var slot_view := get_focused_slot_view()
	if slot_view != null:
		slot_view.focused = mode == Mode.FOCUS
	if mode == Mode.FOCUS:
		_set_cursor_anchor(slot_view)
	elif mode == Mode.MOUSE:
		_set_cursor_anchor(null)


func _set_cursor_anchor(control: Control) -> void:
	var cursor_view := ui.get_cursor_view()
	if cursor_view != null:
		cursor_view.anchor = control


func _visible_views() -> Array[IKContainerView]:
	var result: Array[IKContainerView] = []
	for view in ui.get_container_views():
		if view.is_visible_in_tree() and not view.get_slot_views().is_empty():
			result.append(view)
	return result


## Nearest slot of another view in [param direction], from the screen layout.
func _find_neighbor(direction: Vector2i) -> Array:
	var current := get_focused_slot_view()
	if current == null:
		return []
	var origin := current.get_global_rect().get_center()
	var axis := Vector2(direction)
	var best: Array = []
	var best_score := INF
	for view in _visible_views():
		if view == focused_view:
			continue
		for slot_view in view.get_slot_views():
			var offset := slot_view.get_global_rect().get_center() - origin
			var along := offset.dot(axis)
			if along <= 1.0:
				continue
			var across := (offset - axis * along).length()
			var score := along + across * 2.0
			if score < best_score:
				best_score = score
				best = [view, slot_view.slot]
	return best


func _action_for(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP:
			return Actions.NAV_UP
		Vector2i.DOWN:
			return Actions.NAV_DOWN
		Vector2i.LEFT:
			return Actions.NAV_LEFT
	return Actions.NAV_RIGHT


func _on_slot_pressed(view: IKContainerView, slot_view: IKSlotView, event: InputEventMouseButton) -> void:
	focus_slot(view, slot_view.slot)
	if use_on_double_click and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		# The UI handles this second click first (it puts the stack back), then we use it.
		_use_after_double_click.call_deferred(view, slot_view.slot)


func _use_after_double_click(view: IKContainerView, slot: int) -> void:
	if is_instance_valid(view) and not ui.cursor.is_holding() and not view.container.is_slot_empty(slot):
		_run(use_slot(view, slot))


func _on_ui_visibility_changed() -> void:
	_held_direction = Vector2i.ZERO
	_touch = _Touch.new()
	if ui.is_visible_in_tree() and mode == Mode.FOCUS:
		_ensure_focus.call_deferred()
