extends "res://tests/inventory_kit/ik_test_case.gd"
## Versioned serialization, repair on load, migrations.


func _doc(containers: Dictionary) -> Dictionary:
	return {"format": "inventory_kit", "version": 1, "containers": containers}


func _json_round_trip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func test_round_trip_through_json_preserves_everything() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 6, db)
	var equipment := make_equipment(db)
	bag.add(&"wood", 25)
	bag.add_stack(IKItemStack.new(&"sword", 1, "", {"durability": 37, "ratio": 0.5, "mods": [1, 2.0], "tag": &"fire"}))
	bag.add(&"stone", 3, false, {"wet": true, "level": 2})
	bag.add(&"helmet")
	bag.move_to(bag.find_slots(&"helmet")[0], equipment, 1)
	var doc := _json_round_trip(IKSerializer.to_dict([bag, equipment]))

	var bag2 := IKContainer.new(&"bag", 6, db)
	var equipment2 := make_equipment(db)
	var report := IKSerializer.load_into(doc, [bag2, equipment2])
	assert_true(report.ok, str(report))
	assert_eq(report.warnings.size(), 0, "warnings: %s" % report.warnings)
	assert_eq(bag2.to_debug_array(), bag.to_debug_array())
	assert_eq(equipment2.to_debug_array(), equipment.to_debug_array())
	var sword := bag2.get_stack(bag2.find_slots(&"sword")[0])
	assert_eq(typeof(sword.data["durability"]), TYPE_INT, "ints stay ints")
	assert_eq(typeof(sword.data["mods"][1]), TYPE_FLOAT)
	assert_eq(typeof(sword.data["tag"]), TYPE_STRING_NAME)
	assert_ok(bag2.add(&"stone", 1, false, {"wet": true, "level": 2}))
	assert_eq(bag2.find_slots(&"stone").size(), 1, "loaded stacks still merge with new ones")


func test_v1_fixture_loads() -> void:
	var text := FileAccess.get_file_as_string("res://tests/inventory_kit/fixtures/save_v1.json")
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	var equipment := make_equipment(db)
	var report := IKSerializer.load_into(JSON.parse_string(text), [bag, equipment])
	assert_true(report.ok, str(report))
	assert_eq(report.warnings.size(), 0, "warnings: %s" % report.warnings)
	assert_eq(bag.count(&"wood"), 17)
	assert_eq(bag.get_stack(2).uid, "0123456789abcdef0123456789abcdef")
	assert_eq(bag.get_stack(2).data, {"durability": 37})
	assert_eq(equipment.get_stack(1).item_id, &"helmet")


func test_load_replaces_content_and_keeps_absent_containers() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var chest := IKContainer.new(&"chest", 3, db)
	bag.add(&"gem")
	chest.add(&"stone", 5)
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [{"i": 1, "id": "wood", "n": 2}]}}), [bag, chest])
	assert_true(report.ok)
	assert_eq(bag.get_totals(), {&"wood": 2})
	assert_eq(chest.count(&"stone"), 5, "container absent from the save is untouched")
	assert_eq(report.warnings.size(), 1)


func test_structural_errors_change_nothing() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	bag.add(&"wood", 4)
	var before := bag.to_debug_array()
	var cases := [
		{},
		{"format": "other", "version": 1, "containers": {}},
		{"format": "inventory_kit", "containers": {}},
		{"format": "inventory_kit", "version": 99, "containers": {}},
		{"format": "inventory_kit", "version": 1},
		_doc({"bag": {"slots": [{"i": 0, "id": "stone", "n": 1}]}, "chest": {"slots": "broken"}}),
	]
	for doc in cases:
		var report := IKSerializer.load_into(doc, [bag])
		assert_false(report.ok, "should refuse %s" % doc)
		assert_false(report.error.is_empty())
	assert_eq(bag.to_debug_array(), before)


func test_duplicate_or_empty_container_ids_are_refused() -> void:
	var db := make_db()
	var report := IKSerializer.load_into(_doc({}), [IKContainer.new(&"a", 1, db), IKContainer.new(&"a", 1, db)])
	assert_false(report.ok)
	report = IKSerializer.load_into(_doc({}), [IKContainer.new(&"", 1, db)])
	assert_false(report.ok)


func test_unknown_items_are_kept_and_saved_again() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var saved := {"i": 1, "id": "removed_item", "n": 4, "uid": "", "data": JSON.from_native({"x": 1})}
	saved.erase("uid")
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [saved]}}), [bag])
	assert_true(report.ok)
	assert_eq(report.unknown_items, 1)
	assert_eq(bag.get_stack(1).item_id, &"removed_item")
	assert_eq(IKSerializer.container_to_dict(bag).slots, [saved], "re-saved exactly as loaded")
	assert_code(bag.move(1, 0), IKResult.Code.UNKNOWN_ITEM, "unknown items cannot be moved")
	assert_ok(bag.add(&"wood", 3), "the rest of the container still works")


func test_unknown_items_can_be_dropped() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	var options := IKLoadOptions.new()
	options.keep_unknown_items = false
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [{"i": 0, "id": "ghost", "n": 1}]}}), [bag], options)
	assert_true(report.ok)
	assert_eq(report.dropped, 1)
	assert_true(bag.is_slot_empty(0))


func test_item_aliases_rename_items() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	var options := IKLoadOptions.new()
	options.item_aliases = {&"log": &"wood"}
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [{"i": 0, "id": "log", "n": 6}]}}), [bag], options)
	assert_true(report.ok)
	assert_eq(bag.count(&"wood"), 6)
	assert_eq(report.unknown_items, 0)


func test_oversized_stacks_are_split_then_overflow() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [{"i": 0, "id": "potion", "n": 12}]}}), [bag])
	assert_true(report.ok)
	assert_eq(bag.count(&"potion"), 10)
	assert_eq(report.overflow.size(), 1)
	assert_eq(report.overflow[0].container_id, &"bag")
	assert_eq((report.overflow[0].stack as IKItemStack).amount, 2, "nothing destroyed: 2 potions reported")


func test_shrunk_container_relocates_items() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [
		{"i": 5, "id": "wood", "n": 3},
		{"i": 0, "id": "stone", "n": 1},
		{"i": 0, "id": "gem", "n": 1},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(bag.get_stack(0).item_id, &"stone")
	assert_eq(bag.get_stack(1).item_id, &"wood", "out-of-range slot relocated")
	assert_eq(report.overflow.size(), 1, "gem had a duplicate index and no room left")
	assert_eq(report.warnings.size(), 3)


func test_relocated_items_merge_into_matching_stacks() -> void:
	var bag := IKContainer.new(&"bag", 1, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [
		{"i": 0, "id": "wood", "n": 5},
		{"i": 9, "id": "wood", "n": 4},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(bag.get_stack(0).amount, 9)
	assert_eq(report.overflow.size(), 0)


func test_slot_rule_changes_relocate_items() -> void:
	var db := make_db()
	var equipment := make_equipment(db)
	var report := IKSerializer.load_into(_doc({"equipment": {"slots": [
		{"i": 1, "id": "sword", "n": 1, "uid": "a1"},
	]}}), [equipment])
	assert_true(report.ok)
	assert_eq(equipment.get_stack(0).uid, "a1", "sword moved to the weapon slot")


func test_duplicate_uids_are_removed() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var chest := IKContainer.new(&"chest", 3, db)
	var report := IKSerializer.load_into(_doc({
		"bag": {"slots": [{"i": 0, "id": "sword", "n": 1, "uid": "same"}]},
		"chest": {"slots": [{"i": 0, "id": "sword", "n": 1, "uid": "same"}]},
	}), [bag, chest])
	assert_true(report.ok)
	assert_eq(bag.count(&"sword") + chest.count(&"sword"), 1)
	assert_eq(report.dropped, 1)
	assert_eq(IKAudit.find_duplicate_uids([bag, chest]).size(), 0)


func test_unique_items_without_uid_get_one() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [{"i": 0, "id": "sword", "n": 2}]}}), [bag])
	assert_true(report.ok)
	assert_eq(bag.find_slots(&"sword").size(), 2)
	assert_eq(IKAudit.validate([bag]).size(), 0)


func test_unreadable_entries_are_dropped_and_counted() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [
		"garbage",
		{"i": 0, "n": 3},
		{"i": 1, "id": "wood", "n": 0},
		{"i": 2, "id": "wood", "n": "many"},
		{"i": 3, "id": "wood", "n": 2.5},
		{"i": 3.0, "id": "stone", "n": 4.0, "data": 42},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(report.dropped, 5)
	assert_eq(bag.get_totals(), {&"stone": 4})
	assert_eq(bag.get_stack(3).data, {}, "unreadable data cleared")


func test_plain_json_data_is_accepted() -> void:
	var bag := IKContainer.new(&"bag", 1, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [
		{"i": 0, "id": "sword", "n": 1, "uid": "u", "data": {"durability": 5}},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(bag.get_stack(0).data, {"durability": 5})


func test_load_signals_and_staleness() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	bag.add(&"wood", 2)
	var stale := IKTransaction.new().move(bag, 0, bag, 1)
	var events := []
	bag.slots_changed.connect(func(slots: PackedInt32Array) -> void: events.append(slots))
	bag.item_added.connect(func(_id: StringName, _n: int) -> void: events.append("added"))
	var report := IKSerializer.load_into(_doc({"bag": {"slots": [{"i": 2, "id": "stone", "n": 1}]}}), [bag])
	assert_true(report.ok)
	assert_eq(events, [PackedInt32Array([0, 2])], "no item_added on load")
	assert_code(stale.commit(), IKResult.Code.CONCURRENT_MODIFICATION)
	disconnect_all([bag])


func test_unmatched_containers_are_reported() -> void:
	var bag := IKContainer.new(&"bag", 1, make_db())
	var report := IKSerializer.load_into(_doc({"bag": {"slots": []}, "bank": {"slots": [{"i": 0, "id": "gem", "n": 1}]}}), [bag])
	assert_true(report.ok)
	assert_true(report.unmatched_containers.has(&"bank"))


# --- Migrations ------------------------------------------------------------------

func test_migrations_run_in_order() -> void:
	var migrations := IKMigrations.new()
	migrations.target_version = 3
	migrations.register(1, func(doc: Dictionary) -> Dictionary:
		doc["steps"] = ["1->2"]
		return doc)
	migrations.register(2, func(doc: Dictionary) -> Dictionary:
		doc["steps"].append("2->3")
		return doc)
	var report := IKLoadReport.new()
	var original := {"format": "inventory_kit", "version": 1}
	var result := migrations.migrate(original, report)
	assert_eq(report.error, "")
	assert_eq(report.source_version, 1)
	assert_eq(result.version, 3)
	assert_eq(result.steps, ["1->2", "2->3"])
	assert_false(original.has("steps"), "input document is not modified")


func test_migration_failures() -> void:
	var migrations := IKMigrations.new()
	migrations.target_version = 3
	migrations.register(1, func(doc: Dictionary) -> Dictionary: return doc)
	var report := IKLoadReport.new()
	migrations.migrate({"version": 1}, report)
	assert_true(report.error.contains("v2"), "missing step 2->3: %s" % report.error)
	report = IKLoadReport.new()
	migrations.migrate({"version": 4}, report)
	assert_true(report.error.contains("newer"))
	report = IKLoadReport.new()
	migrations.migrate({"version": "1"}, report)
	assert_false(report.error.is_empty())
	var bad := IKMigrations.new()
	bad.target_version = 2
	bad.register(1, func(_doc: Dictionary) -> Variant: return null)
	report = IKLoadReport.new()
	bad.migrate({"version": 1}, report)
	assert_true(report.error.contains("did not return"))
