class_name IKInputActions
extends RefCounted
## Input actions used by [IKInputController], with default keyboard and gamepad bindings.
##
## [method ensure_defaults] only adds actions that do not exist yet: define an
## action with the same name in Project Settings > Input Map to rebind it.

const NAV_UP := &"ik_nav_up"
const NAV_DOWN := &"ik_nav_down"
const NAV_LEFT := &"ik_nav_left"
const NAV_RIGHT := &"ik_nav_right"
## Pick up / put down (keyboard Enter or Space, gamepad A / Cross).
const PRIMARY := &"ik_primary"
## Take half / put one (keyboard X, gamepad X / Square).
const SECONDARY := &"ik_secondary"
## Send to the other container (keyboard F, gamepad Y / Triangle).
const QUICK_MOVE := &"ik_quick_move"
## Put held items back, or ask to close (keyboard Escape, gamepad B / Circle).
const CANCEL := &"ik_cancel"
## Jump to the previous / next container (keyboard Q / E, gamepad LB / RB).
const PREVIOUS_PANEL := &"ik_previous_panel"
const NEXT_PANEL := &"ik_next_panel"
## Use or equip the selected item (keyboard U, gamepad Back / Select; mouse double click).
const USE := &"ik_use"
## Sort the selected container (keyboard R, gamepad right stick press).
const SORT := &"ik_sort"
## Turn the held item a quarter turn in grid inventories (keyboard T, gamepad left
## stick press; mouse middle click and a second finger tap work too).
const ROTATE := &"ik_rotate"
## Hotbar: select slot 1-9 (number keys), cycle (mouse wheel), use (gamepad right trigger).
const HOTBAR_SLOTS: Array[StringName] = [&"ik_hotbar_1", &"ik_hotbar_2", &"ik_hotbar_3", &"ik_hotbar_4",
	&"ik_hotbar_5", &"ik_hotbar_6", &"ik_hotbar_7", &"ik_hotbar_8", &"ik_hotbar_9"]
const HOTBAR_NEXT := &"ik_hotbar_next"
const HOTBAR_PREVIOUS := &"ik_hotbar_previous"
const HOTBAR_USE := &"ik_hotbar_use"

const STICK_DEADZONE := 0.5


static func ensure_defaults() -> void:
	_ensure(NAV_UP, [_key(KEY_UP), _key(KEY_W), _button(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_ensure(NAV_DOWN, [_key(KEY_DOWN), _key(KEY_S), _button(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_ensure(NAV_LEFT, [_key(KEY_LEFT), _key(KEY_A), _button(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_ensure(NAV_RIGHT, [_key(KEY_RIGHT), _key(KEY_D), _button(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_ensure(PRIMARY, [_key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_ensure(SECONDARY, [_key(KEY_X), _button(JOY_BUTTON_X)])
	_ensure(QUICK_MOVE, [_key(KEY_F), _button(JOY_BUTTON_Y)])
	_ensure(CANCEL, [_key(KEY_ESCAPE), _button(JOY_BUTTON_B)])
	_ensure(PREVIOUS_PANEL, [_key(KEY_Q), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_ensure(NEXT_PANEL, [_key(KEY_E), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_ensure(USE, [_key(KEY_U), _button(JOY_BUTTON_BACK)])
	_ensure(SORT, [_key(KEY_R), _button(JOY_BUTTON_RIGHT_STICK)])
	_ensure(ROTATE, [_key(KEY_T), _button(JOY_BUTTON_LEFT_STICK)])
	for i in HOTBAR_SLOTS.size():
		_ensure(HOTBAR_SLOTS[i], [_key((KEY_1 + i) as Key)])
	_ensure(HOTBAR_NEXT, [_wheel(MOUSE_BUTTON_WHEEL_DOWN)])
	_ensure(HOTBAR_PREVIOUS, [_wheel(MOUSE_BUTTON_WHEEL_UP)])
	_ensure(HOTBAR_USE, [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])


static func navigation_actions() -> Array[StringName]:
	return [NAV_UP, NAV_DOWN, NAV_LEFT, NAV_RIGHT]


static func _ensure(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, STICK_DEADZONE)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = -1  # any gamepad
	return event


static func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


static func _axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	event.device = -1
	return event
