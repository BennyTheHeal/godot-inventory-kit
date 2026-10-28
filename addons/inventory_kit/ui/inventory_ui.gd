class_name IKInventoryUI
extends Control
## Root of an inventory screen. Owns the [IKCursor] (the stack in hand) and turns
## presses on any [IKContainerView] below it into inventory actions.
##
## Mouse controls:
## - Left click: pick up a stack / put the held stack down (merge or swap).
## - Right click: pick up half / put down one item.
## - Shift + left click: quick move to the view's [member IKContainerView.quick_move_target].
## - Drag and drop: press on a slot, release over another one.
## - Middle click (grid inventories): turn the held item a quarter turn.
##
## When the screen is hidden, held items go back where they came from.

## Emitted when an action is refused (full slot, rule...), e.g. to play a sound.
signal interaction_failed(result: IKResult)
## Emitted when an IKContainerView joins this screen.
signal view_registered(view: IKContainerView)
## Emitted when a slot receives a mouse press, before the action runs.
signal slot_pressed(view: IKContainerView, slot_view: IKSlotView, event: InputEventMouseButton)

## Look of every view in this screen (default grey skin when empty). Assigning a new
## skin at runtime restyles the whole screen, held item included.
@export var skin: IKSkin:
	set(value):
		skin = value
		if _cursor_view != null:  # after _ready: restyle what is already built
			_apply_skin()
## Put held items back automatically when this screen is hidden.
@export var return_held_on_hide := true
## Handle mouse events that Godot emulates from touch. A touch controller turns
## this off to handle taps and long presses itself.
var accept_emulated_mouse := true

## Pixels the mouse must travel for a press-and-release to count as a drag.
const DRAG_THRESHOLD := 6.0

var cursor := IKCursor.new()

var _views: Array[IKContainerView] = []
var _cursor_view: IKCursorView
var _press_position := Vector2.ZERO
var _picked_on_press := false


func _ready() -> void:
	if mouse_filter == MOUSE_FILTER_STOP:
		mouse_filter = MOUSE_FILTER_IGNORE
	var start_skin := get_skin()  # before the cursor view exists: the skin setter restyles it
	_cursor_view = IKCursorView.new()
	_cursor_view.name = "CursorView"
	add_child(_cursor_view)
	_cursor_view.setup(cursor, start_skin)
	cursor.container.changed.connect(_redraw_slots)
	visibility_changed.connect(_on_visibility_changed)


func get_skin() -> IKSkin:
	if skin == null:
		skin = IKSkin.create_default()
	return skin


func get_cursor_view() -> IKCursorView:
	return _cursor_view


func _apply_skin() -> void:
	for view in _views:
		if view.container != null:
			view.bind(view.container)  # rebuilds its slots with the new skin
	if _cursor_view != null:
		_cursor_view.set_skin(get_skin())


## Shows or hides the mouse hover style on every slot of this screen.
func set_hover_enabled(enabled: bool) -> void:
	for view in _views:
		for slot_view in view.get_slot_views():
			slot_view.hover_enabled = enabled
		view.update_grid_highlight()


## Turns the held item a quarter turn (grid inventories). Refusals are reported
## through [signal interaction_failed].
func rotate_held() -> IKResult:
	var result := cursor.rotate_held()
	report_result(result)
	return result


## Emits [signal interaction_failed] for a refused result. For input controllers.
func report_result(result: IKResult) -> void:
	if result != null and not result.ok:
		interaction_failed.emit(result)


func get_container_views() -> Array[IKContainerView]:
	return _views


## Puts held items back (origin first, then any container shown in this screen).
func return_held() -> IKResult:
	var fallbacks: Array = []
	for view in _views:
		if view.container != null:
			fallbacks.append(view.container)
	var result := cursor.return_held(fallbacks)
	if not result.ok:
		interaction_failed.emit(result)
	return result


## The slot view under a global position, among visible views of this screen.
func find_slot_view_at(global_point: Vector2) -> IKSlotView:
	for view in _views:
		if not view.is_visible_in_tree():
			continue
		for slot_view in view.get_slot_views():
			if slot_view.get_global_rect().has_point(global_point):
				return slot_view
	return null


func _register_view(view: IKContainerView) -> void:
	if not _views.has(view):
		_views.append(view)
		view_registered.emit(view)
	_on_view_bound(view)


func _unregister_view(view: IKContainerView) -> void:
	_views.erase(view)


func _on_view_bound(view: IKContainerView) -> void:
	if cursor.container.database == null and view.container != null:
		cursor.container.database = view.container.database


func _handle_press(view: IKContainerView, slot_view: IKSlotView, event: InputEventMouseButton) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION and not accept_emulated_mouse:
		return
	slot_pressed.emit(view, slot_view, event)
	var target := slot_view.container
	var slot := slot_view.slot
	_press_position = event.global_position
	_picked_on_press = false
	var result: IKResult
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			var quick_target := view.quick_move_target.container if view.quick_move_target != null else null
			if event.shift_pressed and quick_target != null and not cursor.is_holding():
				result = cursor.quick_move(target, slot, quick_target)
			else:
				var was_holding := cursor.is_holding()
				result = cursor.primary(target, slot)
				_picked_on_press = not was_holding and cursor.is_holding()
		MOUSE_BUTTON_RIGHT:
			result = cursor.secondary(target, slot)
		MOUSE_BUTTON_MIDDLE:
			if not cursor.is_holding():
				return
			result = cursor.rotate_held()
		_:
			return
	_report(result)


func _handle_release(_slot_view: IKSlotView, event: InputEventMouseButton) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION and not accept_emulated_mouse:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not _picked_on_press:
		return
	_picked_on_press = false
	if event.global_position.distance_to(_press_position) < DRAG_THRESHOLD:
		return  # A click: keep holding, the next click places.
	var target := find_slot_view_at(event.global_position)
	if target != null and cursor.is_holding():
		_report(cursor.primary(target.container, target.slot))


func _report(result: IKResult) -> void:
	report_result(result)


func _redraw_slots() -> void:
	for view in _views:
		view.update_grid_highlight()  # classic views: redraws every slot


func _on_visibility_changed() -> void:
	if return_held_on_hide and not is_visible_in_tree() and cursor.is_holding():
		return_held()
