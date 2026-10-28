extends "res://tests/inventory_kit/ik_test_case.gd"
## Keyboard / gamepad / touch control (pro/input).

const A := preload("res://addons/inventory_kit/pro/input/input_actions.gd")

var db: IKItemDatabase
var ui: IKInventoryUI
var bag: IKContainer
var chest: IKContainer
var bag_view: IKContainerView
var chest_view: IKContainerView
var controller: IKInputController


func _build(bag_size: int = 8) -> void:
	db = make_db()
	bag = IKContainer.new(&"bag", bag_size, db)
	chest = IKContainer.new(&"chest", 4, db)
	get_tree().root.size = Vector2i(1280, 720)
	ui = IKInventoryUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 40)
	row.add_theme_constant_override(&"separation", 40)
	ui.add_child(row)
	bag_view = IKContainerView.new()
	bag_view.columns = 4
	row.add_child(bag_view)
	chest_view = IKContainerView.new()
	chest_view.columns = 2
	row.add_child(chest_view)
	bag_view.bind(bag)
	chest_view.bind(chest)
	bag_view.quick_move_target = chest_view
	chest_view.quick_move_target = bag_view
	controller = IKInputController.new()
	controller.repeat_delay = 0.05
	controller.repeat_interval = 0.02
	controller.long_press_time = 0.05
	ui.add_child(controller)
	add_to_tree(ui)
	await wait_frames(3)


func _action(action: StringName, pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	controller._input(event)


func _tap_action(action: StringName) -> void:
	_action(action, true)
	_action(action, false)


func _touch(pressed: bool, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = at
	controller._input(event)


func _drag(at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = at
	controller._input(event)


func _center(view: IKContainerView, slot: int) -> Vector2:
	return view.get_slot_view(slot).get_global_rect().get_center()


func _focus() -> Array:
	return [controller.focused_view, controller.focused_slot]


func test_first_press_shows_selection_then_moves() -> void:
	await _build()
	assert_eq(controller.mode, IKInputController.Mode.MOUSE)
	_tap_action(A.NAV_RIGHT)
	assert_eq(controller.mode, IKInputController.Mode.FOCUS)
	assert_eq(_focus(), [bag_view, 0], "first press does not move")
	assert_true(bag_view.get_slot_view(0).focused)
	assert_eq(bag_view.get_slot_view(0).get_state(), IKSlotView.State.FOCUS)
	var hovered := chest_view.get_slot_view(1)
	hovered._set_hovered(true)
	assert_eq(hovered.get_state(), IKSlotView.State.NORMAL, "no second highlight under the mouse")
	_tap_action(A.NAV_RIGHT)
	assert_eq(_focus(), [bag_view, 1])
	assert_false(bag_view.get_slot_view(0).focused)


func test_grid_navigation() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	for step in [[A.NAV_RIGHT, 1], [A.NAV_DOWN, 5], [A.NAV_LEFT, 4], [A.NAV_UP, 0], [A.NAV_UP, 0], [A.NAV_LEFT, 0]]:
		_tap_action(step[0])
		assert_eq(_focus(), [bag_view, step[1]], "after %s" % step[0])


func test_shorter_last_row() -> void:
	await _build(6)
	controller.focus_slot(bag_view, 2)
	controller.set_mode(IKInputController.Mode.FOCUS)
	_tap_action(A.NAV_DOWN)
	assert_eq(_focus(), [bag_view, 5])


func test_navigation_crosses_to_the_container_on_screen() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 3)
	_tap_action(A.NAV_RIGHT)
	assert_eq(_focus(), [chest_view, 0], "right edge of the bag leads to the chest")
	_tap_action(A.NAV_LEFT)
	assert_eq(_focus(), [bag_view, 3])


func test_actions_pick_place_half_and_quick_move() -> void:
	await _build()
	bag.add(&"stone", 9)
	bag.add(&"wood", 4)
	controller.set_mode(IKInputController.Mode.FOCUS)
	_tap_action(A.PRIMARY)
	assert_true(ui.cursor.is_holding())
	assert_eq(ui.get_cursor_view().anchor, bag_view.get_slot_view(0), "held stack drawn at the selection")
	_tap_action(A.NAV_RIGHT)
	_tap_action(A.NAV_RIGHT)
	_tap_action(A.PRIMARY)
	assert_eq(bag.get_stack(2).amount, 9)
	_tap_action(A.SECONDARY)
	assert_eq(ui.cursor.get_held().amount, 5)
	_tap_action(A.SECONDARY)
	assert_eq(bag.get_stack(2).amount, 5)
	_tap_action(A.PRIMARY)
	_tap_action(A.NAV_LEFT)
	_tap_action(A.QUICK_MOVE)
	assert_eq(chest.count(&"wood"), 4, "slot 1 held the wood")


func test_cancel_returns_held_items_or_requests_close() -> void:
	await _build()
	bag.add(&"wood", 6)
	var closes := [0]
	controller.close_requested.connect(func() -> void: closes[0] += 1)
	controller.set_mode(IKInputController.Mode.FOCUS)
	_tap_action(A.SECONDARY)
	_tap_action(A.NAV_RIGHT)
	_tap_action(A.CANCEL)
	assert_false(ui.cursor.is_holding())
	assert_eq(bag.get_stack(0).amount, 6)
	assert_eq(closes[0], 0)
	_tap_action(A.CANCEL)
	assert_eq(closes[0], 1)
	disconnect_all([controller])


func test_switching_devices_keeps_your_place() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	_tap_action(A.NAV_RIGHT)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	controller._input(motion)
	assert_eq(controller.mode, IKInputController.Mode.MOUSE)
	assert_false(bag_view.get_slot_view(1).focused, "selection hidden while using the mouse")
	assert_true(chest_view.get_slot_view(0).hover_enabled, "mouse hover shown again")
	assert_eq(ui.get_cursor_view().anchor, null)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.global_position = _center(bag_view, 6)
	bag_view.get_slot_view(6)._gui_input(click)
	assert_eq(_focus(), [bag_view, 6], "a click moves the selection")
	_tap_action(A.NAV_LEFT)
	assert_eq(_focus(), [bag_view, 6], "first key press shows it where the mouse left it")
	assert_true(bag_view.get_slot_view(6).focused)


func test_panel_cycling_remembers_slots() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 5)
	_tap_action(A.NEXT_PANEL)
	assert_eq(_focus(), [chest_view, 0])
	_tap_action(A.NAV_DOWN)
	_tap_action(A.PREVIOUS_PANEL)
	assert_eq(_focus(), [bag_view, 5])
	_tap_action(A.NEXT_PANEL)
	assert_eq(_focus(), [chest_view, 2])


func test_held_direction_repeats() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	var press := InputEventAction.new()
	press.action = A.NAV_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().create_timer(0.25).timeout
	var release := InputEventAction.new()
	release.action = A.NAV_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	await wait_frames(2)
	# The first press only shows the selection; every later move comes from the repeat.
	var moved_twice := controller.focused_view == chest_view or controller.focused_slot >= 2
	assert_true(moved_twice, "holding the direction kept moving (now %s)" % [_focus()])
	var position := _focus()
	await wait_frames(5)
	assert_eq(_focus(), position, "stops after release")


func test_touch_tap_pick_and_place() -> void:
	await _build()
	bag.add(&"stone", 3)
	_touch(true, _center(bag_view, 0))
	_touch(false, _center(bag_view, 0))
	assert_true(ui.cursor.is_holding())
	assert_eq(controller.mode, IKInputController.Mode.TOUCH)
	_touch(true, _center(chest_view, 1))
	_touch(false, _center(chest_view, 1))
	assert_eq(chest.count(&"stone"), 3)


func test_touch_drag_moves_a_stack() -> void:
	await _build()
	bag.add(&"wood", 5)
	_touch(true, _center(bag_view, 0))
	_drag(_center(bag_view, 0) + Vector2(30, 0))
	_drag(_center(bag_view, 2))
	_touch(false, _center(bag_view, 2))
	assert_eq(bag.get_stack(2).amount, 5)
	assert_false(ui.cursor.is_holding())


func test_touch_long_press_takes_half() -> void:
	await _build()
	bag.add(&"stone", 8)
	_touch(true, _center(bag_view, 0))
	await get_tree().create_timer(0.15).timeout
	_touch(false, _center(bag_view, 0))
	assert_eq(ui.cursor.get_held().amount, 4, "long press = secondary")


func test_emulated_mouse_is_ignored_when_touch_is_handled() -> void:
	await _build()
	bag.add(&"wood", 2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.device = InputEvent.DEVICE_ID_EMULATION
	click.global_position = _center(bag_view, 0)
	bag_view.get_slot_view(0)._gui_input(click)
	assert_false(ui.cursor.is_holding(), "the touch handler already handles this tap")


func test_inactive_when_hidden_or_disabled() -> void:
	await _build()
	bag.add(&"wood", 2)
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.enabled = false
	_tap_action(A.PRIMARY)
	assert_false(ui.cursor.is_holding())
	controller.enabled = true
	ui.hide()
	_tap_action(A.PRIMARY)
	assert_false(ui.cursor.is_holding())


func test_selection_survives_container_resize() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 2)
	bag.resize(12)
	await wait_frames(2)
	assert_true(bag_view.get_slot_view(2).focused)


func test_default_actions_do_not_override_user_bindings() -> void:
	var custom := &"ik_secondary"
	if InputMap.has_action(custom):
		InputMap.erase_action(custom)
	InputMap.add_action(custom)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	InputMap.action_add_event(custom, key)
	IKInputActions.ensure_defaults()
	assert_eq(InputMap.action_get_events(custom).size(), 1, "user binding kept")
	InputMap.erase_action(custom)
	IKInputActions.ensure_defaults()
	assert_true(InputMap.action_get_events(custom).size() >= 2, "defaults restored for the next tests")


func test_standard_demo_scene_runs() -> void:
	var demo: IKInventoryUI = load("res://demo/standard/standard_demo.tscn").instantiate()
	add_to_tree(demo)
	await wait_frames(2)
	assert_true(demo.get_node("InputController") is IKInputController)
