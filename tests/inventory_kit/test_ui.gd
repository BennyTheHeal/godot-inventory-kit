extends "res://tests/inventory_kit/ik_test_case.gd"
## Views in a real scene tree, with simulated mouse input.

var db: IKItemDatabase
var ui: IKInventoryUI
var bag: IKInventory
var chest: IKInventory
var bag_view: IKContainerView
var chest_view: IKContainerView


func _build() -> void:
	db = make_db()
	for item in db.items:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		item.icon = ImageTexture.create_from_image(image)
	db.get_item(&"wood").description = "A log."
	ui = IKInventoryUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	bag = IKInventory.new()
	bag.container_id = &"bag"
	bag.size = 8
	bag.database = db
	ui.add_child(bag)
	chest = IKInventory.new()
	chest.container_id = &"chest"
	chest.size = 4
	chest.database = db
	ui.add_child(chest)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 20)
	ui.add_child(row)
	bag_view = IKContainerView.new()
	bag_view.columns = 4
	bag_view.inventory = bag
	row.add_child(bag_view)
	chest_view = IKContainerView.new()
	chest_view.columns = 2
	chest_view.inventory = chest
	row.add_child(chest_view)
	bag_view.quick_move_target = chest_view
	# Headless windows are tiny (64x64); use the project's base size so the
	# stretch transform is 1:1 and input coordinates match layout coordinates.
	get_tree().root.size = Vector2i(1280, 720)
	add_to_tree(ui)


func _click(view: IKSlotView, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = view.get_global_rect().get_center()
		event.global_position = event.position
		view._gui_input(event)


func _center(view: IKSlotView) -> Vector2:
	return view.get_global_rect().get_center()


func _push_mouse(button_pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = button_pressed
	event.position = at
	event.global_position = at
	get_tree().root.push_input(event)


func _push_motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(event)


func test_views_build_one_slot_per_container_slot() -> void:
	_build()
	assert_eq(bag_view.get_slot_views().size(), 8)
	assert_eq(chest_view.get_slot_views().size(), 4)
	assert_eq(ui.get_container_views().size(), 2)
	assert_eq(ui.cursor.container.database, db, "cursor picks up the database")


func test_views_follow_container_changes() -> void:
	_build()
	bag.container.add(&"wood", 7)
	var view := bag_view.get_slot_view(0)
	assert_eq(view.get_amount_text(), "7")
	assert_true(view.get_icon_texture() != null)
	assert_eq(view.tooltip_text, "Wood\nA log.")
	bag.container.remove(&"wood", 6)
	assert_eq(view.get_amount_text(), "", "no number for a single item")
	bag.container.remove(&"wood", 1)
	assert_true(view.get_icon_texture() == null, "icon cleared")
	assert_eq(view.tooltip_text, "")


func test_view_bound_before_entering_the_screen() -> void:
	db = make_db()
	var container := IKContainer.new(&"loose", 3, db)
	container.add(&"wood", 2)
	var view := IKContainerView.new()
	view.bind(container)
	assert_eq(view.get_slot_views().size(), 3, "built immediately, even outside the tree")
	var screen := IKInventoryUI.new()
	screen.add_child(view)
	add_to_tree(screen)
	assert_eq(view.get_slot_view(0).cursor, screen.cursor, "gets the screen's cursor on entering it")
	assert_eq(view.get_slot_view(0).get_amount_text(), "2")


func test_assigning_a_skin_restyles_the_screen() -> void:
	_build()
	bag.container.add(&"wood", 3)
	var big := IKSkin.create_default()
	big.slot_size = Vector2(72, 72)
	ui.skin = big
	assert_eq(bag_view.get_slot_view(0).skin, big, "existing views rebuilt with the new skin")
	assert_eq(bag_view.get_slot_view(0).custom_minimum_size, Vector2(72, 72))
	assert_eq(bag_view.get_slot_view(0).get_amount_text(), "3", "content kept")
	assert_eq(ui.get_cursor_view().skin, big, "held item uses it too")


func test_view_rebuilds_on_resize() -> void:
	_build()
	bag.container.resize(12)
	assert_eq(bag_view.get_slot_views().size(), 12)


func test_click_pick_and_click_place() -> void:
	_build()
	bag.container.add(&"stone", 9)
	_click(bag_view.get_slot_view(0))
	assert_true(ui.cursor.is_holding())
	_click(chest_view.get_slot_view(3))
	assert_eq(chest.container.count(&"stone"), 9)
	assert_false(ui.cursor.is_holding())


func test_right_click_half_and_one() -> void:
	_build()
	bag.container.add(&"stone", 9)
	_click(bag_view.get_slot_view(0), MOUSE_BUTTON_RIGHT)
	assert_eq(ui.cursor.get_held().amount, 5)
	_click(bag_view.get_slot_view(1), MOUSE_BUTTON_RIGHT)
	assert_eq(bag.container.get_stack(1).amount, 1)
	assert_eq(ui.cursor.get_held().amount, 4)


func test_shift_click_quick_moves() -> void:
	_build()
	bag.container.add(&"wood", 5)
	_click(bag_view.get_slot_view(0), MOUSE_BUTTON_LEFT, true)
	assert_eq(chest.container.count(&"wood"), 5)
	assert_false(ui.cursor.is_holding())


func test_refused_action_emits_interaction_failed() -> void:
	_build()
	var equipment := make_equipment(db)
	var equipment_view := IKContainerView.new()
	ui.add_child(equipment_view)
	equipment_view.bind(equipment)
	bag.container.add(&"wood", 1)
	var failures := []
	ui.interaction_failed.connect(func(result: IKResult) -> void: failures.append(result.code))
	_click(bag_view.get_slot_view(0))
	var target := equipment_view.get_slot_view(0)
	target._set_hovered(true)
	assert_eq(target.get_state(), IKSlotView.State.REJECTED, "hover shows the slot refuses wood")
	_click(target)
	assert_eq(failures, [IKResult.Code.RULE_REJECTED])
	assert_true(ui.cursor.is_holding())


func test_drag_and_drop_with_real_input_events() -> void:
	_build()
	bag.container.add(&"wood", 4)
	await wait_frames(3)  # let containers lay out the slots
	var from := _center(bag_view.get_slot_view(0))
	var to := _center(chest_view.get_slot_view(1))
	assert_true(from != to, "slots are laid out")
	_push_motion(from)
	_push_mouse(true, from)
	_push_motion(to)
	_push_mouse(false, to)
	await wait_frames(1)
	assert_eq(chest.container.get_stack(1).amount, 4, "dropped on the slot under the mouse")
	assert_false(ui.cursor.is_holding())


func test_hiding_the_screen_returns_held_items() -> void:
	_build()
	bag.container.add(&"wood", 6)
	_click(bag_view.get_slot_view(0), MOUSE_BUTTON_RIGHT)
	assert_true(ui.cursor.is_holding())
	ui.hide()
	assert_false(ui.cursor.is_holding())
	assert_eq(bag.container.count(&"wood"), 6)


func test_cursor_view_shows_held_stack() -> void:
	_build()
	bag.container.add(&"stone", 3)
	var cursor_view: IKCursorView = ui.get_node("CursorView")
	assert_false(cursor_view.visible)
	_click(bag_view.get_slot_view(0))
	assert_true(cursor_view.visible)
	_click(bag_view.get_slot_view(0))
	assert_false(cursor_view.visible)


func test_inventory_node_initial_items() -> void:
	db = make_db()
	var node := IKInventory.new()
	node.size = 3
	node.database = db
	node.initial_items = {&"wood": 25, &"gem": 1}
	add_to_tree(node)
	assert_eq(node.container.count(&"wood"), 25)
	assert_eq(node.container.count(&"gem"), 1)


func test_lite_demo_scene_runs() -> void:
	var demo: IKInventoryUI = load("res://demo/lite/lite_demo.tscn").instantiate()
	add_to_tree(demo)
	await wait_frames(2)
	assert_eq(demo.get_container_views().size(), 2)
	assert_true(demo.bag.container.count(&"wood_log") > 0)


func test_held_item_follows_the_pointer_in_a_moved_canvas_layer() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var layer := CanvasLayer.new()
	layer.offset = Vector2(200, 100)
	layer.scale = Vector2(1.5, 1.5)
	add_to_tree(layer)
	var holder := Control.new()
	holder.position = Vector2(80, 40)
	layer.add_child(holder)
	var ui := IKInventoryUI.new()
	ui.size = Vector2(600, 400)
	holder.add_child(ui)
	var bag := IKContainer.new(&"bag", 4, make_db())
	bag.add(&"wood", 3)
	var view := IKContainerView.new()
	ui.add_child(view)
	view.bind(bag)
	await wait_frames()
	ui.cursor.pick(bag, 0)
	await wait_frames(2)
	var cursor_view := ui.get_cursor_view()
	var center := cursor_view.get_global_transform_with_canvas() * (cursor_view.size / 2.0)
	var pointer := get_tree().root.get_mouse_position()
	assert_true(center.distance_to(pointer) < 1.0, "held item drawn at %s, pointer at %s" % [center, pointer])
