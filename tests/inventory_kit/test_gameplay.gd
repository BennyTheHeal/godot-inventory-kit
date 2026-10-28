extends "res://tests/inventory_kit/ik_test_case.gd"
## 1.1 gameplay modules: set bonuses, equipment comparison, slot feedback, world items,
## dropping and pickup notifications.


func _set_db() -> IKItemDatabase:
	var db := make_db()
	db.get_item(&"helmet").properties = {"armor": 3}
	for piece in [["iron_helmet", &"head", 4], ["iron_chest", &"body", 8], ["iron_gloves", &"hands", 2], ["iron_boots", &"feet", 2]]:
		var item := make_item(StringName(piece[0]), 1, true, &"armor", piece[1])
		item.properties = {"armor": piece[2], "set": "iron"}
		db.add_item(item)
	return db


func _bonuses() -> IKSetBonusList:
	var list := IKSetBonusList.new()
	list.bonuses = [IKSetBonus.new(&"iron", 4, {"armor": 10}), IKSetBonus.new(&"iron", 2, {"armor": 4})]
	return list


func _equipment(db: IKItemDatabase) -> IKEquipment:
	var equipment := IKEquipment.new()
	equipment.slot_types = [&"head", &"body", &"hands", &"feet", &"weapon"]
	equipment.database = db
	equipment.set_bonuses = _bonuses()
	add_to_tree(equipment)
	return equipment


func _texts(node: Node, into: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		into.append(node.text)
	for child in node.get_children():
		_texts(child, into)
	return into


# --- Set bonuses ----------------------------------------------------------------------

func test_set_bonuses_follow_worn_pieces() -> void:
	var db := _set_db()
	var equipment := _equipment(db)
	var bag := IKContainer.new(&"bag", 8, db)
	var events: Array = []
	equipment.set_bonus_changed.connect(func(bonus: IKSetBonus, active: bool) -> void: events.append([bonus.pieces_required, active]))
	for id in [&"iron_helmet", &"iron_chest", &"iron_gloves", &"iron_boots"]:
		bag.add(id)
	assert_ok(equipment.equip_from(bag, 0))
	assert_eq(equipment.count_set_pieces(&"iron"), 1)
	assert_eq(equipment.sum_property(&"armor"), 4.0, "one piece: no bonus")
	assert_ok(equipment.equip_from(bag, 1))
	assert_eq(equipment.sum_property(&"armor"), 4.0 + 8.0 + 4.0, "two pieces: +4")
	assert_eq(equipment.sum_property(&"armor", false), 12.0, "bonuses can be left out")
	assert_ok(equipment.equip_from(bag, 2))
	assert_ok(equipment.equip_from(bag, 3))
	assert_eq(equipment.sum_property(&"armor"), 16.0 + 4.0 + 10.0, "four pieces: both bonuses")
	assert_eq(equipment.get_active_set_bonuses().size(), 2)
	assert_ok(equipment.unequip(&"feet", bag))
	assert_eq(equipment.sum_property(&"armor"), 14.0 + 4.0)
	assert_eq(events, [[2, true], [4, true], [4, false]])
	equipment.set_bonuses = null
	assert_eq(equipment.get_active_set_bonuses().size(), 0, "removing the list clears the bonuses")


func test_set_bonus_list_helpers() -> void:
	var list := _bonuses()
	var iron := list.get_for_set(&"iron")
	assert_eq(iron.size(), 2)
	assert_eq(iron[0].pieces_required, 2, "sorted by pieces")
	assert_eq(list.get_full_size(&"iron"), 4)
	assert_eq(list.get_full_size(&"gold"), 0)
	assert_eq(iron[0].describe(), "+4 Armor")
	assert_eq(iron[0].get_set_name(), "Iron set")


# --- Tooltip comparison -------------------------------------------------------------

func test_tooltip_compares_with_worn_item() -> void:
	var db := _set_db()
	var equipment := _equipment(db)
	var bag := IKContainer.new(&"bag", 8, db)
	bag.add(&"helmet")
	bag.add(&"iron_helmet")
	var tooltip := IKTooltip.new()
	tooltip.shown_properties = [&"armor"]
	tooltip.equipment = equipment
	add_to_tree(tooltip)

	tooltip.show_stack(bag.get_stack(1), db.get_item(&"iron_helmet"), bag)
	var texts := _texts(tooltip)
	assert_true(texts.has("Armor: 4") and texts.has("+4"), "nothing worn compares with 0: %s" % texts)
	assert_true(texts.has("Nothing worn in this slot"), str(texts))

	equipment.equip_from(bag, 0)  # helmet, armor 3
	tooltip.show_stack(bag.get_stack(1), db.get_item(&"iron_helmet"), bag)
	texts = _texts(tooltip)
	assert_true(texts.has("+1") and texts.has("Compared with Helmet"), str(texts))
	var difference := tooltip.find_child("Difference", true, false) as Label
	assert_true(difference != null and difference.get_theme_color(&"font_color") == IKTooltip.BETTER_COLOR)

	tooltip.show_stack(IKItemStack.new(&"iron_gloves", 1, "g"), db.get_item(&"iron_gloves"), bag)
	assert_false(_texts(tooltip).has("Compared with Helmet"), "only the same slot type is compared")

	tooltip.show_stack(equipment.container.get_stack(0), db.get_item(&"helmet"), equipment.container)
	texts = _texts(tooltip)
	assert_false(texts.has("Compared with Helmet"), "worn items are not compared with themselves")
	assert_true(tooltip.find_child("Difference", true, false) == null)


func test_tooltip_lists_set_bonuses() -> void:
	var db := _set_db()
	var equipment := _equipment(db)
	var bag := IKContainer.new(&"bag", 8, db)
	bag.add(&"iron_helmet")
	bag.add(&"iron_chest")
	equipment.equip_from(bag, 0)
	equipment.equip_from(bag, 1)
	var tooltip := IKTooltip.new()
	tooltip.equipment = equipment
	add_to_tree(tooltip)
	tooltip.show_stack(equipment.container.get_stack(0), db.get_item(&"iron_helmet"), equipment.container)
	var texts := _texts(tooltip)
	assert_true(texts.has("Iron set (2/4)"), str(texts))
	assert_true(texts.has("  (2) +4 Armor") and texts.has("  (4) +10 Armor"), str(texts))


# --- World items --------------------------------------------------------------------

func test_world_item_partial_pickup() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 1, db)
	var item := IKWorldItem2D.spawn(add_to_tree(Node2D.new()), IKItemStack.new(&"wood", 30), db, Vector2(10, 10), 0.0)
	var collected: Array = []
	item.picked_up.connect(func(_container: IKContainer, amount: int) -> void: collected.append(amount))
	var result := item.pick_up(bag)
	assert_ok(result)
	assert_eq(result.remainder, 10)
	assert_eq(bag.count(&"wood"), 20)
	assert_eq(item.get_item_stack().amount, 10, "the rest stays on the ground")
	assert_false(item.is_queued_for_deletion())
	assert_code(item.pick_up(bag), IKResult.Code.CONTAINER_FULL)
	bag.resize(2)
	assert_ok(item.pick_up(bag))
	assert_true(item.is_queued_for_deletion(), "freed once empty")
	assert_eq(collected, [20, 10])


func test_world_item_keeps_unique_identity() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	var sword := IKItemStack.new(&"sword", 1, "abc123", {"durability": 7})
	var item := IKWorldItem3D.spawn(add_to_tree(Node3D.new()), sword, db, Vector3(1, 0, 2), 0.0)
	assert_eq(item.global_position, Vector3(1, 0, 2))
	assert_ok(item.pick_up(bag))
	assert_true(IKItemStack.same(bag.get_stack(0), sword), "uid and data survive the trip")
	var copy := IKWorldItem2D.spawn(add_to_tree(Node2D.new()), sword, db, Vector2.ZERO, 0.0)
	assert_false(copy.pick_up(bag).ok, "the same uid cannot be collected twice")
	assert_eq(bag.count(&"sword"), 1)


func test_collector_inventory_is_found() -> void:
	var db := make_db()
	var body := CharacterBody2D.new()
	var bag := IKInventory.new()
	bag.database = db
	body.add_child(bag)
	add_to_tree(body)
	assert_eq(IKPickup.find_container(body), bag.container, "IKInventory child")
	assert_eq(IKPickup.find_container(bag), bag.container)
	var item := IKWorldItem2D.spawn(add_to_tree(Node2D.new()), IKItemStack.new(&"stone", 3), db, Vector2.ZERO, 0.0)
	item._on_body_entered(body)
	assert_eq(bag.container.count(&"stone"), 0, "bodies outside the collector group are ignored")
	body.add_to_group(&"player")
	item.pickup_delay = 1.0
	item._on_body_entered(body)
	assert_eq(bag.container.count(&"stone"), 0, "not during the pickup delay")
	item.pickup_delay = 0.0
	item._on_body_entered(body)
	assert_eq(bag.container.count(&"stone"), 0, "a body that touched it during the delay must step away first")
	item.body_exited.emit(body)
	item._on_body_entered(body)
	assert_eq(bag.container.count(&"stone"), 3)


func test_dropper_moves_the_held_stack_into_the_world() -> void:
	var db := make_db()
	var level := add_to_tree(Node2D.new()) as Node2D
	var hero := Node2D.new()
	hero.position = Vector2(100, 100)
	level.add_child(hero)
	var ui := IKInventoryUI.new()
	add_to_tree(ui)
	var bag := IKContainer.new(&"bag", 4, db)
	var view := IKContainerView.new()
	ui.add_child(view)
	view.bind(bag)
	var dropper := IKItemDropper.new()
	dropper.spawn_parent = level
	dropper.drop_origin = hero
	ui.add_child(dropper)
	bag.add(&"sword")
	var sword := bag.get_stack(0)
	assert_eq(dropper.drop_held(), null, "nothing held")
	ui.cursor.pick(bag, 0)
	var world_item := dropper.drop_held() as IKWorldItem2D
	assert_true(world_item != null and world_item.get_parent() == level)
	assert_false(ui.cursor.is_holding())
	assert_eq(bag.count(&"sword"), 0)
	assert_true(IKItemStack.same(world_item.get_item_stack(), sword))
	assert_true(world_item.global_position.distance_to(hero.global_position) <= dropper.scatter + 0.01)
	assert_true(world_item.pickup_delay > 0.0, "cannot be picked straight back")

	dropper.spawn_parent = null
	var dropped: Array = []
	dropper.item_dropped.connect(func(stack: IKItemStack, node: Node) -> void: dropped.append([stack.item_id, node]))
	bag.add(&"wood", 5)
	ui.cursor.pick(bag, 0)
	dropper.drop_held()
	assert_eq(dropped, [[&"wood", null]], "without a spawn parent the game gets the stack")


# --- Notifications and feedback -----------------------------------------------------

func test_pickup_notifier_merges_lines() -> void:
	var db := make_db()
	var notifier := IKPickupNotifier.new()
	var screen := Control.new()
	add_to_tree(screen)
	notifier.hide_while = screen
	add_to_tree(notifier)
	var bag := IKContainer.new(&"bag", 4, db)
	notifier.watch(bag)
	bag.add(&"wood", 3)
	assert_eq(_texts(notifier).size(), 0, "changes made while the inventory screen is open are not shown")
	screen.visible = false
	bag.add(&"wood", 2)
	bag.add(&"wood", 4)
	bag.add(&"stone", 1)
	assert_eq(_texts(notifier), PackedStringArray(["+6 Wood", "+1 Stone"]))
	var item := IKWorldItem2D.spawn(add_to_tree(Node2D.new()), IKItemStack.new(&"gem", 1), db, Vector2.ZERO, 0.0)
	var other := IKContainer.new(&"other", 4, db)
	item.pick_up(other)
	assert_true(_texts(notifier).has("+1 Gem"), "world pickups are shown automatically")
	notifier._process(10.0)
	await wait_frames()
	assert_eq(notifier.get_child_count(), 0, "lines expire")


func test_slot_feedback_pops_and_shakes() -> void:
	var db := make_db()
	var ui := IKInventoryUI.new()
	ui.size = Vector2(400, 300)
	add_to_tree(ui)
	var bag := IKContainer.new(&"bag", 4, db)
	var equipment := make_equipment(db)
	var view := IKContainerView.new()
	ui.add_child(view)
	view.bind(bag)
	var gear_view := IKContainerView.new()
	ui.add_child(gear_view)
	gear_view.bind(equipment)
	var feedback := IKSlotFeedback.new()
	ui.add_child(feedback)
	await wait_frames()
	bag.add(&"wood", 3)
	await wait_frames()
	var icon := view.get_slot_view(0).get_node(^"Icon") as Control
	assert_true(icon.scale.x > 1.0, "received slot pops (scale %s)" % icon.scale)
	assert_eq(feedback.get_child_count(), 0, "no sound player")

	ui.cursor.pick(bag, 0)
	await wait_frames()
	var target := gear_view.get_slot_view(0)
	ui.slot_pressed.emit(gear_view, target, InputEventMouseButton.new())
	ui.report_result(ui.cursor.place(equipment, 0))
	await wait_frames()
	assert_true(target.self_modulate != Color.WHITE, "refused slot flashes")


func test_shipped_set_bonuses_match_the_catalog() -> void:
	var path := "res://addons/inventory_kit/art/shared/set_bonuses.tres"
	var db_path := "res://addons/inventory_kit/art/painted/painted_items.tres"
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(db_path):
		return
	var list: IKSetBonusList = load(path)
	var db: IKItemDatabase = load(db_path)
	assert_eq(list.bonuses.size(), 16)
	for bonus in list.bonuses:
		var pieces := 0
		for id in db.get_ids():
			var item := db.get_item(id)
			if StringName(str(item.properties.get("set", ""))) == bonus.set_id:
				pieces += 1
		assert_eq(pieces, 4, "set %s" % bonus.set_id)
		assert_true(bonus.pieces_required in [2, 4])


func test_dropped_item_waits_for_the_player_to_step_away() -> void:
	var db := make_db()
	var level := add_to_tree(Node2D.new()) as Node2D
	var body := CharacterBody2D.new()
	body.add_to_group(&"player")
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	body.add_child(shape)
	var bag := IKInventory.new()
	bag.database = db
	body.add_child(bag)
	level.add_child(body)
	body.global_position = Vector2(300, 300)
	IKWorldItem2D.spawn(level, IKItemStack.new(&"wood", 2), db, Vector2(310, 300), 0.1)
	for i in 20:
		await get_tree().physics_frame
	assert_eq(bag.container.count(&"wood"), 0, "not collected while the player still stands on it")
	body.global_position = Vector2(800, 300)
	for i in 4:
		await get_tree().physics_frame
	body.global_position = Vector2(305, 300)
	for i in 4:
		await get_tree().physics_frame
	assert_eq(bag.container.count(&"wood"), 2, "collected when the player comes back")


func test_rich_tooltip_and_sets_are_translatable() -> void:
	var locale := TranslationServer.get_locale()
	var french := Translation.new()
	french.locale = "fr"
	for pair in [["Iron Helmet", "Casque en fer"], ["Helmet", "Heaume"], ["Armor", "Armure"], ["%s: %s", "%s : %s"],
			["Compared with %s", "Comparé à %s"], ["%s set", "Ensemble %s"], ["Iron", "de fer"],
			["%s %s", "%s %s"], ["Too heavy.", "Trop lourd."]]:
		french.add_message(pair[0], pair[1])
	TranslationServer.add_translation(french)
	TranslationServer.set_locale("fr")
	var db := _set_db()
	var equipment := _equipment(db)
	var bag := IKContainer.new(&"bag", 8, db)
	bag.add(&"helmet")
	bag.add(&"iron_helmet")
	equipment.equip_from(bag, 0)
	var tooltip := IKTooltip.new()
	tooltip.shown_properties = [&"armor"]
	tooltip.equipment = equipment
	add_to_tree(tooltip)
	tooltip.show_stack(bag.get_stack(1), db.get_item(&"iron_helmet"), bag)
	var texts := _texts(tooltip)
	assert_true(texts.has("Casque en fer") and texts.has("Armure : 4") and texts.has("Comparé à Heaume"), str(texts))
	assert_true(texts.has("Ensemble de fer (0/4)") and texts.has("  (2) +4 Armure"), str(texts))
	db.get_item(&"stone").weight = 50.0
	var heavy := IKContainer.new(&"heavy", 4, db)
	heavy.rules.append(IKWeightRule.new(10.0))
	assert_eq(IKText.result_message(heavy.add(&"stone")), "Trop lourd.")
	TranslationServer.remove_translation(french)
	TranslationServer.set_locale(locale)
