extends "res://tests/inventory_kit/ik_test_case.gd"
## Grid views with the mouse (Lite): multi-cell drawing, picking from any cell,
## drop preview, swaps, middle-click rotation, held item size.

var db: IKItemDatabase
var ui: IKInventoryUI
var bag: IKContainer
var chest: IKContainer
var bag_view: IKContainerView
var chest_view: IKContainerView
var failures: Array[IKResult] = []


func _build() -> void:
	db = make_grid_db()
	for item in db.items:
		var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)  # wide: turning it is visible
		image.fill(Color.WHITE)
		item.icon = ImageTexture.create_from_image(image)
	bag = IKContainer.create_grid(&"bag", 4, 3, db)
	chest = IKContainer.new(&"chest", 4, db)
	get_tree().root.size = Vector2i(1280, 720)
	ui = IKInventoryUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 20)
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
	add_to_tree(ui)
	ui.interaction_failed.connect(func(result: IKResult) -> void: failures.append(result))
	await wait_frames(2)


func _click(view: IKSlotView, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.shift_pressed = shift
		event.position = view.get_global_rect().get_center()
		event.global_position = event.position
		view._gui_input(event)


func _cell(slot: int) -> IKSlotView:
	return bag_view.get_slot_view(slot)


func test_grid_view_has_one_view_per_cell() -> void:
	await _build()
	assert_true(bag_view.is_grid())
	assert_eq(bag_view.get_slot_views().size(), 12)
	assert_eq(bag_view.columns, 4, "columns follow the grid width")
	assert_eq(_cell(5).owner_view, bag_view)
	assert_false(chest_view.is_grid())


func test_anchor_draws_the_item_over_its_cells() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	await wait_frames(1)
	var skin := ui.get_skin()
	var icon := _cell(0).get_node(^"Icon") as Control
	var tall := 3 * skin.slot_size.y + 2 * skin.slot_separation - 2 * skin.icon_margin
	assert_eq(icon.size.y, tall, "icon spans three cells")
	assert_eq(icon.size.x, skin.slot_size.x - 2 * skin.icon_margin)
	assert_true(_cell(0).get_icon_texture() != null)
	assert_eq(_cell(4).get_icon_texture(), null, "covered cells draw nothing of their own")
	assert_eq(_cell(4).get_item_stack().item_id, &"sword", "but report the item over them")
	assert_eq(_cell(8).get_item_definition().id, &"sword")
	assert_eq(_cell(8).get_anchor_slot(), 0)
	assert_eq(_cell(8).get_display_view(), _cell(0))
	assert_true(_cell(4).tooltip_text.contains("Sword"), _cell(4).tooltip_text)
	assert_eq(_cell(1).get_item_stack(), null)
	assert_eq((_cell(1).get_node(^"Icon") as Control).size.y, skin.slot_size.y - 2 * skin.icon_margin)


func test_click_on_a_covered_cell_picks_the_item_and_click_places_its_top_left() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	_click(_cell(8))
	assert_true(ui.cursor.is_holding())
	assert_eq(ui.cursor.origin_slot, 0, "origin is the item's top-left cell")
	assert_eq(grid_map(bag), "..../..../....")
	_click(_cell(1))
	assert_false(ui.cursor.is_holding())
	assert_eq(grid_map(bag), ".S../.S../.S..")


func test_drop_preview_shows_where_the_held_item_lands() -> void:
	await _build()
	assert_ok(bag.add(&"helmet"))
	_click(_cell(5))
	assert_true(ui.cursor.is_holding())
	_cell(1)._set_hovered(true)
	assert_eq(bag_view.get_active_slot(), 1)
	assert_eq(bag_view.get_preview_cells().keys().size(), 4)
	assert_true(bag_view.is_preview_valid())
	_cell(1)._set_hovered(false)
	_cell(3)._set_hovered(true)
	assert_eq(bag_view.get_preview_cells().keys().size(), 2, "only the cells inside the grid")
	assert_false(bag_view.is_preview_valid(), "sticks out on the right")
	_cell(3)._set_hovered(false)
	assert_eq(bag_view.get_preview_cells().size(), 0, "nothing hovered, no preview")


func test_preview_accepts_a_swap_but_not_two_items() -> void:
	await _build()
	assert_ok(bag.add(&"gem"))
	assert_ok(bag.add(&"potion"))
	assert_ok(bag.add(&"sword"))
	assert_eq(grid_map(bag), "gpS./..S./..S.")
	_click(_cell(2))
	_cell(1)._set_hovered(true)
	assert_true(bag_view.is_preview_valid(), "over the potion only: swap")
	_cell(1)._set_hovered(false)
	_cell(0)._set_hovered(true)
	assert_true(bag_view.is_preview_valid(), "over the gem only")
	ui.cursor.rotate_held()
	assert_false(bag_view.is_preview_valid(), "turned, it covers the gem and the potion")


func test_click_swaps_with_the_item_under_the_held_one() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.add(&"gem"))
	_click(_cell(1))
	assert_eq(ui.cursor.get_held().item_id, &"gem")
	_click(_cell(4), MOUSE_BUTTON_LEFT)
	assert_eq(ui.cursor.get_held().item_id, &"sword", "the sword is now in hand")
	assert_eq(ui.cursor.origin_slot, 0, "and comes from cell 0")
	assert_eq(grid_map(bag), "..../g.../....")
	_click(_cell(1))
	assert_eq(grid_map(bag), ".S../gS../.S..")


func test_refused_drop_reports_the_fit_text() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	_click(_cell(0))
	_click(_cell(8))
	assert_true(ui.cursor.is_holding(), "still in hand")
	assert_eq(failures.size(), 1)
	assert_eq(IKText.result_message(failures[0]), "It does not fit there.")


func test_middle_click_turns_the_held_item() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	var cursor_view := ui.get_cursor_view()
	_click(_cell(0))
	assert_eq(cursor_view.get_held_cells(), Vector2i(1, 3))
	var skin := ui.get_skin()
	assert_eq(cursor_view.size.y, 3 * skin.slot_size.y + 2 * skin.slot_separation, "held item drawn at its size")
	_click(_cell(0), MOUSE_BUTTON_MIDDLE)
	assert_true(ui.cursor.get_held().rotated)
	assert_eq(cursor_view.get_held_cells(), Vector2i(3, 1))
	assert_eq(cursor_view.size.x, 3 * skin.slot_size.x + 2 * skin.slot_separation)
	_click(_cell(4))
	assert_eq(grid_map(bag), "..../SSS./....")
	assert_eq(_cell(4).get_icon_texture().get_size(), Vector2(4, 8), "the icon is turned too")
	_click(_cell(5), MOUSE_BUTTON_MIDDLE)
	assert_eq(failures.size(), 0, "middle click with empty hands does nothing")


func test_rotate_held_with_nothing_held_fails_quietly() -> void:
	await _build()
	assert_code(ui.rotate_held(), IKResult.Code.SLOT_EMPTY)


func test_drag_and_drop_in_a_grid() -> void:
	await _build()
	assert_ok(bag.add(&"helmet"))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = _cell(4).get_global_rect().get_center()
	press.position = press.global_position
	_cell(4)._gui_input(press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.global_position = _cell(6).get_global_rect().get_center()
	release.position = release.global_position
	_cell(4)._gui_input(release)
	assert_false(ui.cursor.is_holding())
	assert_eq(grid_map(bag), "..../..HH/..HH")


func test_shift_click_on_a_covered_cell_sends_the_item() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	_click(_cell(8), MOUSE_BUTTON_LEFT, true)
	assert_eq(chest.count(&"sword"), 1)
	assert_eq(bag.count(&"sword"), 0)
	_click(chest_view.get_slot_view(0))
	_click(_cell(10))
	assert_eq(grid_map(bag), "..../..../....", "the sword does not fit from row 3")
	assert_true(ui.cursor.is_holding())
	_click(_cell(2))
	assert_eq(bag.get_anchor(10), 2)


func test_right_click_on_a_covered_cell_takes_half() -> void:
	await _build()
	assert_ok(bag.add(&"plank", 9))
	_click(_cell(1), MOUSE_BUTTON_RIGHT)
	assert_eq(ui.cursor.get_held().amount, 5)
	assert_eq(bag.get_stack(0).amount, 4)
	_click(_cell(1), MOUSE_BUTTON_LEFT)
	assert_eq(bag.get_stack(0).amount, 9, "dropped back on the same item: merged")
	assert_false(ui.cursor.is_holding())


func test_hiding_the_screen_returns_a_turned_item() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.add(&"helmet"))
	_click(_cell(0))
	ui.rotate_held()
	ui.hide()
	assert_false(ui.cursor.is_holding())
	assert_eq(bag.count(&"sword"), 1)
	assert_eq(IKAudit.validate([bag, ui.cursor.container]).size(), 0)


func test_filter_dims_every_cell_of_an_item() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.add(&"gem"))
	bag_view.filter = func(stack: IKItemStack, _definition: IKItemDefinition) -> bool: return stack.item_id == &"gem"
	assert_true(_cell(0).dimmed)
	assert_true(_cell(8).dimmed, "covered cells too")
	assert_false(_cell(1).dimmed)
	assert_false(_cell(2).dimmed, "free cells are never dimmed")


func test_view_follows_moves_and_resizes() -> void:
	await _build()
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.move(0, 3))
	assert_eq(_cell(0).get_item_stack(), null, "old cells refreshed")
	assert_eq(_cell(7).get_item_stack().item_id, &"sword")
	assert_ok(bag.resize(16))
	assert_eq(bag_view.get_slot_views().size(), 16)
	assert_eq(_cell(11).get_item_stack().item_id, &"sword")


func test_skin_change_keeps_the_grid() -> void:
	await _build()
	assert_ok(bag.add(&"helmet"))
	var skin := IKSkin.create_default()
	skin.slot_size = Vector2(40, 40)
	ui.skin = skin
	await wait_frames(1)
	assert_eq(bag_view.columns, 4)
	var icon := _cell(0).get_node(^"Icon") as Control
	assert_eq(icon.size.x, float(2 * 40 + skin.slot_separation - 2 * skin.icon_margin))


func test_classic_views_are_unchanged() -> void:
	await _build()
	assert_ok(chest.add(&"sword"))
	await wait_frames(1)
	var skin := ui.get_skin()
	var icon := chest_view.get_slot_view(0).get_node(^"Icon") as Control
	assert_eq(icon.size, skin.slot_size - Vector2.ONE * 2 * skin.icon_margin, "one slot, whatever the grid size")
	assert_eq(chest_view.columns, 2)


func test_rotated_texture_is_cached_and_turned() -> void:
	var image := Image.create(6, 2, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var turned := IKSlotView.rotated_texture(texture)
	assert_eq(turned.get_size(), Vector2(2, 6))
	assert_true(IKSlotView.rotated_texture(texture) == turned, "cached")
	assert_eq(IKSlotView.rotated_texture(null), null)
