extends "res://tests/inventory_kit/ik_test_case.gd"
## Standard modules: weight, sort, filters, consumables, equipment, hotbar, chest, tooltips.

const A := preload("res://addons/inventory_kit/pro/input/input_actions.gd")


class Patient extends Node:
	var health := 50
	var calls: Array = []

	func can_heal(_amount: int) -> bool:
		return health < 100

	func heal(amount: int) -> void:
		health = mini(100, health + amount)
		calls.append(["heal", amount])


func _weighted_db() -> IKItemDatabase:
	var db := make_db()
	db.get_item(&"wood").weight = 2.0
	db.get_item(&"stone").weight = 5.0
	db.get_item(&"sword").weight = 8.0
	return db


func _potion_db() -> IKItemDatabase:
	var db := make_db()
	var potion := IKUsableItem.new()
	potion.id = &"heal_potion"
	potion.display_name = "Healing Potion"
	potion.max_stack = 5
	potion.category = &"consumable"
	var effect := IKCallMethodEffect.new()
	effect.method = &"heal"
	effect.arguments = [30]
	effect.check_method = &"can_heal"
	potion.effects = [effect]
	db.add_item(potion)
	var scroll := IKUsableItem.new()
	scroll.id = &"map"
	scroll.consume_on_use = false
	db.add_item(scroll)
	return db


# --- Weight ---------------------------------------------------------------------

func test_weight_limit_refuses_heavy_changes() -> void:
	var bag := IKContainer.new(&"bag", 10, _weighted_db())
	bag.rules.append(IKWeightRule.new(20.0))
	assert_ok(bag.add(&"wood", 5))
	assert_eq(IKWeightRule.weight_of(bag), 10.0)
	assert_code(bag.add(&"stone", 3), IKResult.Code.RULE_REJECTED)
	assert_ok(bag.add(&"stone", 2))
	assert_code(bag.add(&"wood", 1), IKResult.Code.RULE_REJECTED, "exactly at the limit")
	assert_eq(bag.count(&"stone"), 2)


func test_overloaded_bag_can_still_be_emptied() -> void:
	var db := _weighted_db()
	var bag := IKContainer.new(&"bag", 10, db)
	var chest := IKContainer.new(&"chest", 10, db)
	bag.add(&"stone", 10)  # 50 kg, no rule yet
	bag.rules.append(IKWeightRule.new(20.0))
	assert_ok(bag.remove(&"stone", 1), "lighter is always allowed")
	assert_ok(bag.transfer_to(0, chest, 2))
	assert_code(bag.add(&"wood", 1), IKResult.Code.RULE_REJECTED, "heavier is not")
	assert_ok(bag.move(0, 5), "moving inside does not change the weight")


func test_remaining_capacity() -> void:
	var bag := IKContainer.new(&"bag", 10, _weighted_db())
	bag.rules.append(IKWeightRule.new(23.0))
	bag.add(&"stone", 2)
	assert_eq(IKWeightRule.remaining_capacity(bag, &"wood"), 6)
	assert_eq(IKWeightRule.remaining_capacity(bag, &"gem"), -1, "weightless item")
	var amount := IKWeightRule.remaining_capacity(bag, &"stone")
	assert_ok(bag.add(&"stone", amount))
	assert_code(bag.add(&"stone", 1), IKResult.Code.RULE_REJECTED)


# --- Sort and filters -------------------------------------------------------------

func test_sort_merges_and_orders_by_category() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 8, db)
	var tx := IKTransaction.new()
	tx.add(bag, &"wood", 5).add(bag, &"potion", 2).add(bag, &"sword")
	tx.commit()
	bag.add(&"wood", 5, false, {"wet": true})
	bag.move(0, 6)
	bag.add(&"wood", 4)  # lands in slot 0, separate from slot 6
	var totals := bag.get_totals()
	var sword_uid := bag.get_stack(bag.find_slots(&"sword")[0]).uid
	assert_ok(IKSorter.sort(bag))
	assert_eq(bag.get_totals(), totals, "nothing created or lost")
	var order := []
	for i in bag.size():
		var stack := bag.get_stack(i)
		order.append(null if stack == null else [stack.item_id, stack.amount])
	assert_eq(order, [[&"potion", 2], [&"wood", 9], [&"wood", 5], [&"sword", 1], null, null, null, null],
		"categories alphabetically; plain wood merged, wet wood kept apart")
	assert_eq(bag.get_stack(3).uid, sword_uid)
	assert_ok(IKSorter.sort(bag, IKSorter.Mode.CATEGORY, [&"weapon", &"material"]))
	assert_eq([bag.get_stack(0).item_id, bag.get_stack(1).item_id, bag.get_stack(3).item_id], [&"sword", &"wood", &"potion"],
		"custom category order, unlisted categories last")


func test_sort_modes() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	bag.add(&"stone", 3)
	bag.add(&"wood", 9)
	bag.add(&"gem")
	IKSorter.sort(bag, IKSorter.Mode.AMOUNT)
	assert_eq(bag.get_stack(0).item_id, &"wood")
	IKSorter.sort(bag, IKSorter.Mode.NAME)
	assert_eq([bag.get_stack(0).item_id, bag.get_stack(1).item_id, bag.get_stack(2).item_id], [&"gem", &"stone", &"wood"])


func test_sort_keeps_ruled_slots_and_unknown_items_in_place() -> void:
	var db := make_db()
	var mixed := IKContainer.new(&"mixed", 4, db)
	mixed.set_slot_rule(0, IKEquipSlotRule.new(&"weapon"))
	IKSerializer.load_into({"format": "inventory_kit", "version": 1, "containers": {"mixed": {"slots": [
		{"i": 0, "id": "sword", "n": 1, "uid": "s1"},
		{"i": 1, "id": "stone", "n": 2},
		{"i": 2, "id": "relic", "n": 1},
		{"i": 3, "id": "gem", "n": 1},
	]}}}, [mixed])
	assert_ok(IKSorter.sort(mixed, IKSorter.Mode.NAME))
	assert_eq(mixed.get_stack(0).uid, "s1")
	assert_eq(mixed.get_stack(2).item_id, &"relic", "unknown item untouched")
	assert_eq(mixed.get_stack(1).item_id, &"gem")
	assert_eq(mixed.get_stack(3).item_id, &"stone")


func test_rearrange_cannot_create_items() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"wood", 3)
	var forged := [IKItemStack.new(&"wood", 3), IKItemStack.new(&"wood", 3)]
	assert_code(IKTransaction.new().rearrange(bag, forged).commit(), IKResult.Code.INVARIANT_VIOLATION)
	assert_code(IKTransaction.new().rearrange(bag, [null]).commit(), IKResult.Code.INVALID_ARGUMENT)
	assert_eq(bag.count(&"wood"), 3)


func test_filters() -> void:
	var db := make_db()
	db.get_item(&"potion").tags = [&"healing"]
	var wood := IKItemStack.new(&"wood", 1)
	var potion := IKItemStack.new(&"potion", 1)
	var sword := IKItemStack.new(&"sword", 1)
	var by_category := IKItemFilter.category(&"consumable")
	assert_true(by_category.call(potion, db.get_item(&"potion")))
	assert_false(by_category.call(wood, db.get_item(&"wood")))
	assert_true(IKItemFilter.tag(&"healing").call(potion, db.get_item(&"potion")))
	assert_true(IKItemFilter.equippable(&"weapon").call(sword, db.get_item(&"sword")))
	assert_false(IKItemFilter.equippable().call(wood, db.get_item(&"wood")))
	assert_true(IKItemFilter.text("POT").call(potion, db.get_item(&"potion")))
	assert_true(IKItemFilter.text("heal").call(potion, db.get_item(&"potion")), "matches tags")
	assert_true(IKItemFilter.text("").call(wood, db.get_item(&"wood")))
	assert_false(IKItemFilter.all([by_category, IKItemFilter.text("wood")]).call(potion, db.get_item(&"potion")))
	assert_true(IKItemFilter.any([by_category, IKItemFilter.text("wood")]).call(wood, db.get_item(&"wood")))


func test_view_filter_dims_non_matching_items() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add(&"wood", 2)
	bag.add(&"potion", 2)
	var view := IKContainerView.new()
	view.bind(bag)
	add_to_tree(view)
	view.filter = IKItemFilter.category(&"consumable")
	assert_true(view.get_slot_view(0).dimmed)
	assert_false(view.get_slot_view(1).dimmed)
	assert_false(view.get_slot_view(2).dimmed, "empty slots are not dimmed")
	bag.move(1, 0)  # swap: the filter follows the items
	assert_false(view.get_slot_view(0).dimmed)
	assert_true(view.get_slot_view(1).dimmed)
	view.filter = Callable()
	assert_false(view.get_slot_view(1).dimmed)


# --- Consumables ------------------------------------------------------------------

func test_using_a_potion_consumes_one_and_applies_effects() -> void:
	var db := _potion_db()
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add(&"heal_potion", 3)
	var patient := Patient.new()
	assert_true(IKItemUser.can_use(bag, 0, patient))
	assert_ok(IKItemUser.use(bag, 0, patient))
	assert_eq(bag.count(&"heal_potion"), 2)
	assert_eq(patient.health, 80)
	assert_ok(IKItemUser.use(bag, 0, patient))
	assert_eq(patient.health, 100)
	assert_code(IKItemUser.use(bag, 0, patient), IKResult.Code.NOT_USABLE, "full health: refused")
	assert_eq(bag.count(&"heal_potion"), 1, "nothing consumed when refused")
	assert_eq(patient.calls.size(), 2)
	patient.free()


func test_use_refusals() -> void:
	var db := _potion_db()
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add(&"wood")
	bag.add(&"heal_potion")
	bag.add(&"map")
	assert_code(IKItemUser.use(bag, 0), IKResult.Code.NOT_USABLE, "not an IKUsableItem")
	assert_code(IKItemUser.use(bag, 3), IKResult.Code.SLOT_EMPTY)
	assert_code(IKItemUser.use(bag, 1, null), IKResult.Code.NOT_USABLE, "no user to heal")
	assert_ok(IKItemUser.use(bag, 2))
	assert_eq(bag.count(&"map"), 1, "consume_on_use = false")


# --- Equipment, hotbar, chest -------------------------------------------------------

func _equipment(db: IKItemDatabase) -> IKEquipment:
	var equipment := IKEquipment.new()
	equipment.slot_types = [&"head", &"weapon", &"ring", &"ring"]
	equipment.database = db
	add_to_tree(equipment)
	return equipment


func test_equipment_slots_follow_slot_types() -> void:
	var db := make_db()
	db.get_item(&"sword").properties = {"damage": 7}
	db.get_item(&"helmet").properties = {"armor": 2}
	var equipment := _equipment(db)
	assert_eq(equipment.container.size(), 4)
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add(&"sword", 2)
	bag.add(&"helmet")
	var events := []
	equipment.equipped.connect(func(slot: StringName, stack: IKItemStack) -> void: events.append(["+", slot, stack.item_id]))
	equipment.unequipped.connect(func(slot: StringName, stack: IKItemStack) -> void: events.append(["-", slot, stack.item_id]))
	assert_ok(equipment.equip_from(bag, 0))
	assert_ok(equipment.equip_from(bag, 2))
	assert_eq(equipment.sum_property(&"damage"), 7.0)
	assert_eq(equipment.sum_property(&"armor"), 2.0)
	var first_sword := equipment.get_equipped(&"weapon").uid
	assert_ok(equipment.equip_from(bag, 1), "second sword swaps with the first")
	assert_eq(bag.get_stack(1).uid, first_sword)
	assert_code(equipment.equip_from(bag, 1).code if false else bag.add(&"wood"), IKResult.Code.OK)
	assert_code(equipment.equip_from(bag, bag.find_slots(&"wood")[0]), IKResult.Code.RULE_REJECTED)
	assert_ok(equipment.unequip(&"head", bag))
	assert_eq(events, [["+", &"weapon", &"sword"], ["+", &"head", &"helmet"], ["-", &"weapon", &"sword"],
		["+", &"weapon", &"sword"], ["-", &"head", &"helmet"]])
	disconnect_all([equipment])


func test_hotbar_selection_and_use() -> void:
	var db := _potion_db()
	var hotbar := IKHotbar.new()
	hotbar.size = 4
	hotbar.database = db
	var patient := Patient.new()
	hotbar.user = patient
	add_to_tree(hotbar)
	add_to_tree(patient)
	var view := IKContainerView.new()
	view.bind(hotbar.container)
	add_to_tree(view)
	hotbar.view = view
	assert_true(view.get_slot_view(0).marked)
	hotbar.select(5)
	assert_eq(hotbar.selected, 1, "wraps around")
	assert_true(view.get_slot_view(1).marked)
	assert_false(view.get_slot_view(0).marked)
	hotbar.select_previous()
	hotbar.select_previous()
	assert_eq(hotbar.selected, 3)
	var key := InputEventAction.new()
	key.action = A.HOTBAR_SLOTS[2]
	key.pressed = true
	hotbar._unhandled_input(key)
	assert_eq(hotbar.selected, 2)
	hotbar.container.add_stack(IKItemStack.new(&"heal_potion", 2))  # slot 0
	hotbar.container.move(0, 2)
	assert_ok(hotbar.use_selected())
	assert_eq(patient.health, 80)
	assert_eq(hotbar.container.count(&"heal_potion"), 1)
	hotbar.container.resize(6)
	assert_true(view.get_slot_view(2).marked, "selection kept after a rebuild")


func test_chest_take_all_and_open_state() -> void:
	var db := make_db()
	var chest := IKChest.new()
	chest.size = 4
	chest.database = db
	chest.initial_items = {&"wood": 30, &"gem": 1}
	add_to_tree(chest)
	var opened := [0]
	chest.opened.connect(func() -> void: opened[0] += 1)
	chest.open()
	chest.open()
	assert_true(chest.is_open)
	assert_eq(opened[0], 1)
	chest.toggle()
	assert_false(chest.is_open)
	var bag := IKContainer.new(&"bag", 2, db)
	var result := chest.take_all(bag)
	assert_ok(result)
	assert_eq(result.remainder, 1, "both wood stacks fit, the gem stays")
	assert_eq(bag.count(&"wood"), 30)
	assert_eq(chest.container.count(&"gem"), 1)
	assert_code(chest.take_all(bag), IKResult.Code.CONTAINER_FULL)
	assert_false(chest.is_empty())
	disconnect_all([chest])


# --- Tooltips and slot visuals ------------------------------------------------------

func _texts(node: Node, into: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		into.append(node.text)
	for child in node.get_children():
		_texts(child, into)
	return into


func test_rich_tooltip_content() -> void:
	var db := make_db()
	var sword := db.get_item(&"sword")
	sword.description = "Sharp."
	sword.properties = {"damage": 12, "rarity": "rare"}
	sword.weight = 6.0
	var tooltip := IKTooltip.new()
	tooltip.shown_properties = [&"damage"]
	tooltip.shown_data = [&"durability"]
	add_to_tree(tooltip)
	tooltip.show_stack(IKItemStack.new(&"sword", 1, "u", {"durability": 40}), sword)
	var texts := _texts(tooltip)
	assert_true(texts.has("Sword"), str(texts))
	assert_true(texts.has("Rare · Weapon · Slot: Weapon"), str(texts))
	assert_true(texts.has("Damage: 12"), str(texts))
	assert_true(texts.has("Durability: 40"), str(texts))
	assert_true(texts.has("Sharp."), str(texts))
	assert_true(texts.has("Weight 6"), str(texts))


func test_tooltip_presenter_installs_on_every_slot() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	bag.add(&"wood", 2)
	var ui := IKInventoryUI.new()
	var view := IKContainerView.new()
	ui.add_child(view)
	view.bind(bag)
	var presenter := IKTooltipPresenter.new()
	ui.add_child(presenter)
	add_to_tree(ui)
	var tooltip: Object = view.get_slot_view(0)._make_custom_tooltip("")
	assert_true(tooltip is IKTooltip)
	assert_true((tooltip as IKTooltip).get_theme_stylebox(&"panel") is StyleBoxEmpty,
		"mouse tooltips draw no panel of their own: Godot's TooltipPanel already frames them")
	assert_eq(view.get_slot_view(1)._make_custom_tooltip(""), null, "no tooltip for empty slots")
	if tooltip is Node:
		tooltip.free()
	bag.resize(5)
	assert_true(view.get_slot_view(4).tooltip_factory.is_valid(), "rebuilt slots get it too")


func test_empty_slot_placeholder() -> void:
	var db := make_db()
	var equipment := make_equipment(db)
	var view := IKContainerView.new()
	var outline := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	view.empty_icons.assign([outline])
	view.bind(equipment)
	add_to_tree(view)
	assert_eq(view.get_slot_view(0).get_icon_texture(), null, "placeholder is not an item icon")
	assert_true(view.get_slot_view(0).get_node("Icon").texture == outline)
	var bag := IKContainer.new(&"bag", 2, db)
	bag.add(&"sword")
	bag.move_to(0, equipment, 0)
	assert_true(view.get_slot_view(0).get_icon_texture() != outline)


# --- Controller actions ---------------------------------------------------------------

func _screen(db: IKItemDatabase) -> Array:
	get_tree().root.size = Vector2i(1280, 720)
	var ui := IKInventoryUI.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var equipment := IKEquipment.new()
	equipment.slot_types = [&"head", &"weapon"]
	equipment.database = db
	ui.add_child(equipment)
	var bag := IKContainer.new(&"bag", 6, db)
	var row := HBoxContainer.new()
	ui.add_child(row)
	var bag_view := IKContainerView.new()
	bag_view.columns = 3
	row.add_child(bag_view)
	bag_view.bind(bag)
	var equipment_view := IKContainerView.new()
	equipment_view.inventory = equipment
	row.add_child(equipment_view)
	var patient := Patient.new()
	ui.add_child(patient)
	var controller := IKInputController.new()
	controller.use_target = patient
	controller.equipment = equipment
	ui.add_child(controller)
	add_to_tree(ui)
	await wait_frames(2)
	return [ui, controller, bag, bag_view, equipment, equipment_view, patient]


func _press(controller: IKInputController, action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		controller._input(event)


func test_use_action_uses_equips_and_unequips() -> void:
	var parts: Array = await _screen(_potion_db())
	var controller: IKInputController = parts[1]
	var bag: IKContainer = parts[2]
	var bag_view: IKContainerView = parts[3]
	var equipment: IKEquipment = parts[4]
	var equipment_view: IKContainerView = parts[5]
	var patient: Patient = parts[6]
	bag.add(&"heal_potion", 2)
	bag.add(&"sword")
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 0)
	_press(controller, A.USE)
	assert_eq(patient.health, 80)
	assert_eq(bag.count(&"heal_potion"), 1)
	controller.focus_slot(bag_view, 1)
	_press(controller, A.USE)
	assert_eq(equipment.get_equipped(&"weapon").item_id, &"sword")
	controller.focus_slot(equipment_view, 1)
	_press(controller, A.USE)
	assert_eq(bag.count(&"sword"), 1, "using worn gear takes it off")
	assert_true(equipment.container.is_slot_empty(1))


func test_double_click_uses_the_item() -> void:
	var parts: Array = await _screen(_potion_db())
	var ui: IKInventoryUI = parts[0]
	var bag: IKContainer = parts[2]
	var bag_view: IKContainerView = parts[3]
	var patient: Patient = parts[6]
	bag.add(&"heal_potion", 3)
	var slot_view := bag_view.get_slot_view(0)
	for double in [false, true]:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.double_click = double
		press.global_position = slot_view.get_global_rect().get_center()
		slot_view._gui_input(press)
		var release := press.duplicate()
		release.pressed = false
		release.double_click = false
		slot_view._gui_input(release)
	await wait_frames(1)
	assert_false(ui.cursor.is_holding())
	assert_eq(bag.count(&"heal_potion"), 2)
	assert_eq(patient.health, 80)


func test_sort_action() -> void:
	var parts: Array = await _screen(make_db())
	var controller: IKInputController = parts[1]
	var bag: IKContainer = parts[2]
	var bag_view: IKContainerView = parts[3]
	bag.add(&"sword")
	bag.add(&"wood", 3)
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 0)
	_press(controller, A.SORT)
	assert_eq(bag.get_stack(0).item_id, &"wood")


func test_focus_tooltip_follows_selection() -> void:
	var parts: Array = await _screen(make_db())
	var ui: IKInventoryUI = parts[0]
	var controller: IKInputController = parts[1]
	var bag: IKContainer = parts[2]
	var bag_view: IKContainerView = parts[3]
	var presenter := IKTooltipPresenter.new()
	ui.add_child(presenter)
	await wait_frames(2)
	bag.add(&"wood", 2)
	controller.set_mode(IKInputController.Mode.FOCUS)
	controller.focus_slot(bag_view, 0)
	await wait_frames(2)
	var tooltip: IKTooltip = presenter._focus_tooltip
	assert_true(tooltip.visible)
	assert_true(_texts(tooltip).has("Wood"))
	controller.focus_slot(bag_view, 1)
	await wait_frames(2)
	assert_false(tooltip.visible, "hidden on an empty slot")
	controller.set_mode(IKInputController.Mode.MOUSE)
	controller.focus_slot(bag_view, 0)
	await wait_frames(2)
	assert_false(tooltip.visible, "mouse mode uses Godot's own tooltips")
