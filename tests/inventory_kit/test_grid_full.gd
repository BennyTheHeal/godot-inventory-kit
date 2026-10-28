extends "res://tests/inventory_kit/ik_test_case.gd"
## Grid inventories with the Full modules: keyboard / gamepad / touch, sorting,
## tooltips, feedback and the grid demo scene.

const A := preload("res://addons/inventory_kit/pro/input/input_actions.gd")

var db: IKItemDatabase
var ui: IKInventoryUI
var bag: IKContainer
var chest: IKContainer
var bag_view: IKContainerView
var chest_view: IKContainerView
var controller: IKInputController


func _build() -> void:
	db = make_grid_db()
	bag = IKContainer.create_grid(&"bag", 4, 3, db)
	chest = IKContainer.new(&"chest", 4, db)
	get_tree().root.size = Vector2i(1280, 720)
	ui = IKInventoryUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 40)
	row.add_theme_constant_override(&"separation", 40)
	ui.add_child(row)
	bag_view = IKContainerView.new()
	row.add_child(bag_view)
	chest_view = IKContainerView.new()
	chest_view.columns = 2
	row.add_child(chest_view)
	bag_view.bind(bag)
	chest_view.bind(chest)
	bag_view.quick_move_target = chest_view
	chest_view.quick_move_target = bag_view
	controller = IKInputController.new()
	ui.add_child(controller)
	add_to_tree(ui)
	await wait_frames(3)


func _tap_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		controller._input(event)


func _touch(index: int, pressed: bool, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	controller._input(event)


func _texts(node: Node, into: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		into.append(node.text)
	for child in node.get_children():
		_texts(child, into)
	return into


func test_rotate_action_is_registered() -> void:
	A.ensure_defaults()
	assert_true(InputMap.has_action(A.ROTATE))
	assert_true(InputMap.action_get_events(A.ROTATE).size() >= 2, "keyboard and gamepad")


func test_navigation_jumps_over_the_cells_of_an_item() -> void:
	await _build()
	assert_ok(bag.add(&"gem"))
	assert_ok(bag.add(&"helmet"))  # cells 1, 2, 5, 6
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 0)
	controller.move_focus(Vector2i.RIGHT)
	assert_eq(controller.focused_slot, 1, "onto the helmet")
	assert_true(bag_view.is_focus_active())
	assert_eq(bag_view.get_active_slot(), 1)
	controller.move_focus(Vector2i.RIGHT)
	assert_eq(controller.focused_slot, 3, "one press goes past the whole helmet")
	controller.move_focus(Vector2i.DOWN)
	controller.move_focus(Vector2i.LEFT)
	assert_eq(controller.focused_slot, 6, "entering an item from the side")
	controller.move_focus(Vector2i.LEFT)
	assert_eq(controller.focused_slot, 4)
	controller.move_focus(Vector2i.DOWN)
	assert_eq(controller.focused_slot, 8)


func test_navigation_is_cell_by_cell_while_holding() -> void:
	await _build()
	assert_ok(bag.add(&"helmet"))
	assert_ok(bag.add(&"gem"))
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 2)
	_tap_action(A.PRIMARY)
	assert_eq(ui.cursor.get_held().item_id, &"gem")
	controller.focus_slot(bag_view, 0)
	controller.move_focus(Vector2i.RIGHT)
	assert_eq(controller.focused_slot, 1, "cell by cell, to aim the drop")
	assert_eq(bag_view.get_preview_cells().keys(), [1])
	assert_true(bag_view.is_preview_valid(), "a swap with the helmet")


func test_navigation_leaves_the_grid_at_its_edge() -> void:
	await _build()
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 3)
	controller.move_focus(Vector2i.RIGHT)
	assert_eq(controller.focused_view, chest_view)


func test_keyboard_pick_rotate_and_place() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 8)
	_tap_action(A.PRIMARY)
	assert_eq(ui.cursor.get_held().item_id, &"sword", "picked from a covered cell")
	_tap_action(A.ROTATE)
	assert_true(ui.cursor.get_held().rotated)
	controller.focus_slot(bag_view, 4)
	_tap_action(A.PRIMARY)
	assert_eq(grid_map(bag), "..../SSS./....")


func test_rotate_action_with_empty_hands_is_not_consumed() -> void:
	await _build()
	var event := InputEventAction.new()
	event.action = A.ROTATE
	event.pressed = true
	assert_false(controller._handle_action(event))


func test_second_finger_turns_the_held_item() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	var cell: IKSlotView = bag_view.get_slot_view(4)
	var at := cell.get_global_rect().get_center()
	_touch(0, true, at)
	_touch(0, false, at)
	assert_true(ui.cursor.is_holding(), "tap on a covered cell picks the item")
	_touch(1, true, at)
	assert_true(ui.cursor.get_held().rotated, "second finger: rotate")
	_touch(1, false, at)


func test_use_from_a_covered_cell_equips_the_item() -> void:
	await _build()
	var equipment := IKEquipment.new()
	equipment.slot_types = [&"weapon"]
	equipment.database = db
	ui.add_child(equipment)
	controller.equipment = equipment
	assert_ok(bag.add(&"sword"))
	assert_ok(controller.use_slot(bag_view, 8))
	assert_eq(equipment.container.count(&"sword"), 1)
	assert_eq(bag.count(&"sword"), 0)


func test_sort_packs_a_grid() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.add(&"potion", 3))
	assert_ok(bag.add(&"gem"))
	assert_ok(bag.move(0, 3))
	var totals := bag.get_totals()
	assert_ok(IKSorter.sort(bag))
	assert_eq(grid_map(bag), "pgS./..S./..S.", "consumable, valuable, weapon; packed from the top-left")
	assert_eq(bag.get_totals(), totals)
	assert_eq(IKAudit.validate([bag]).size(), 0)


func test_sort_turns_items_back_and_merges() -> void:
	var grid := IKContainer.create_grid(&"bag", 3, 3, make_grid_db())
	assert_ok(grid.add(&"plank", 8))
	assert_ok(grid.split(0, 3))           # second stack at cell 3
	assert_ok(grid.add(&"sword"))         # cells 2, 5, 8
	assert_ok(grid.rotate(3))             # the 3 planks stand up: cells 3, 6
	assert_eq(grid_map(grid), "==S/=.S/=.S")
	assert_ok(IKSorter.sort(grid, IKSorter.Mode.NAME))
	assert_eq(grid.find_slots(&"plank").size(), 1, "the two plank stacks merged")
	assert_eq(grid.count(&"plank"), 8)
	assert_eq(IKAudit.validate([grid]).size(), 0)
	assert_eq(grid_map(grid), "==S/..S/..S")


func test_sort_keeps_unknown_items_in_place() -> void:
	var grid := IKContainer.create_grid(&"bag", 3, 2, make_grid_db())
	var report := IKSerializer.load_into({"format": "inventory_kit", "version": IKMigrations.CURRENT_VERSION,
		"containers": {"bag": {"size": 6, "slots": [{"i": 0, "id": "ghost", "n": 1}, {"i": 4, "id": "gem", "n": 1}]}}},
		[grid])
	assert_true(report.ok)
	assert_ok(IKSorter.sort(grid))
	assert_eq(grid.get_stack(0).item_id, &"ghost")
	assert_eq(grid.get_stack(1).item_id, &"gem")


func test_sort_moves_big_items_to_the_top() -> void:
	var grid := IKContainer.create_grid(&"bag", 2, 3, make_grid_db())
	assert_ok(grid.add(&"gem"))
	assert_ok(grid.add(&"crate"))
	assert_eq(grid_map(grid), "g./CC/CC")
	assert_ok(IKSorter.sort(grid))
	assert_eq(grid_map(grid), "CC/CC/g.", "materials first, then valuables")


func test_sort_with_classic_slots_is_unchanged() -> void:
	var classic := IKContainer.new(&"bag", 4, make_grid_db())
	assert_ok(classic.add(&"gem"))
	assert_ok(classic.add(&"armor"))
	assert_ok(IKSorter.sort(classic))
	assert_eq(classic.get_stack(0).item_id, &"armor")
	assert_eq(classic.get_stack(1).item_id, &"gem")


func test_tooltip_of_a_covered_cell_describes_the_item() -> void:
	await _build()
	var presenter := IKTooltipPresenter.new()
	ui.add_child(presenter)
	await wait_frames(1)
	assert_ok(bag.add(&"sword"))
	var tooltip := presenter._build_for_slot(bag_view.get_slot_view(8))
	assert_true(_texts(tooltip).has("Sword"), str(_texts(tooltip)))
	tooltip.free()


func test_selection_tooltip_follows_items_in_a_grid() -> void:
	await _build()
	var presenter := IKTooltipPresenter.new()
	ui.add_child(presenter)
	assert_ok(bag.add(&"helmet"))
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 5)
	await wait_frames(2)
	assert_true(presenter._focus_tooltip.visible, "covered cell selected: tooltip shown")


func test_refusal_shakes_the_cell_that_draws_the_item() -> void:
	await _build()
	var feedback := IKSlotFeedback.new()
	ui.add_child(feedback)
	await wait_frames(1)
	assert_ok(bag.add(&"helmet"))
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 5)
	ui.report_result(IKResult.failure(IKResult.Code.SLOT_OCCUPIED, "test"))
	assert_true(bag_view.get_slot_view(0).self_modulate != Color.WHITE, "the anchor flashes")
	assert_eq(bag_view.get_slot_view(5).self_modulate, Color.WHITE)


func test_grid_demo_scene_runs() -> void:
	var demo: IKInventoryUI = load("res://demo/grid/grid_demo.tscn").instantiate()
	add_to_tree(demo)
	await wait_frames(3)
	assert_true(demo.backpack.container.is_grid())
	assert_eq(demo.backpack.container.get_grid_width(), 10)
	assert_false(demo.belt.container.is_grid(), "the belt keeps classic slots")
	assert_eq(demo.backpack_view.get_slot_views().size(), 60)
	assert_true(demo.backpack.container.count(&"sword") == 1)
	assert_true(demo.backpack.container.get_item_size(demo.backpack.container.find_slots(&"sword")[0]).y == 3 \
		or demo.backpack.container.get_stack(demo.backpack.container.find_slots(&"sword")[0]).rotated)
	assert_eq(IKAudit.validate(demo._containers()).size(), 0)
	var totals := IKAudit.totals(demo._containers())
	assert_ok(IKSorter.sort(demo.backpack.container))
	for i in 5:
		demo._on_loot()
	assert_eq(IKAudit.validate(demo._containers()).size(), 0)
	assert_true(IKAudit.totals(demo._containers()).size() >= totals.size())
	assert_true(demo.get_node("InputController") is IKInputController)


func test_standard_demo_links_to_the_grid_demo() -> void:
	var demo: IKInventoryUI = load("res://demo/standard/standard_demo.tscn").instantiate()
	add_to_tree(demo)
	await wait_frames(1)
	var found := false
	for button in demo.find_children("*", "Button", true, false):
		if (button as Button).text == "Grid inventory demo":
			found = true
	assert_true(found)
