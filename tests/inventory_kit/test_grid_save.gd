extends "res://tests/inventory_kit/ik_test_case.gd"
## Saving and loading grid containers: positions, rotation, repairs, old saves.

const DIR := "user://ik_tests_grid"


func _doc(containers: Dictionary) -> Dictionary:
	return {"format": "inventory_kit", "version": IKMigrations.CURRENT_VERSION, "containers": containers}


## Helmet 2x2 at 0, plank 2x1 at 2, wood at 4, sword turned (3x1) at 7 with data.
func _layout(db: IKItemDatabase) -> IKContainer:
	var bag := IKContainer.create_grid(&"bag", 5, 3, db)
	assert_ok(bag.add(&"helmet"))          # 0, 1, 5, 6
	assert_ok(bag.add(&"plank", 7))        # 2, 3
	var sword := IKItemStack.new(&"sword", 1, "sword-uid", {"durability": 12})
	sword.rotated = true
	assert_ok(bag.add_stack(sword))        # turned 3x1: 7, 8, 9
	assert_ok(bag.add(&"wood", 3))         # 4
	assert_eq(grid_map(bag), "HH==w/HHSSS/.....")
	return bag


func test_round_trip_keeps_cells_and_rotation() -> void:
	var db := make_grid_db()
	var bag := _layout(db)
	var text := JSON.stringify(IKSerializer.to_dict([bag]))
	var loaded := IKContainer.create_grid(&"bag", 5, 3, db)
	var report := IKSerializer.load_into(JSON.parse_string(text), [loaded])
	assert_true(report.ok, str(report))
	assert_eq(report.warnings.size(), 0, str(report.warnings))
	assert_eq(loaded.to_debug_array(), bag.to_debug_array())
	assert_eq(grid_map(loaded), "HH==w/HHSSS/.....")
	assert_true(loaded.get_stack(7).rotated)
	assert_eq(loaded.get_stack(7).data, {"durability": 12})
	assert_eq(IKAudit.validate([loaded]).size(), 0)


func test_rotation_is_saved_only_when_turned() -> void:
	var db := make_grid_db()
	var entries: Array = IKSerializer.container_to_dict(_layout(db))["slots"]
	var turned := 0
	for entry in entries:
		if entry.has("rot"):
			turned += 1
			assert_eq(entry["rot"], true)
	assert_eq(turned, 1, "only the sword is turned")
	var classic := IKContainer.new(&"bag", 3, make_db())
	assert_ok(classic.add(&"wood", 5))
	assert_false(IKSerializer.container_to_dict(classic)["slots"][0].has("rot"), "classic saves keep the 1.1 format")


func test_old_save_loads_into_a_grid() -> void:
	var text := FileAccess.get_file_as_string("res://tests/inventory_kit/fixtures/save_v1.json")
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 4, 3, db)
	var report := IKSerializer.load_into(JSON.parse_string(text), [bag])
	assert_true(report.ok, str(report))
	assert_eq(report.warnings.size(), 0, str(report.warnings))
	assert_true(report.unmatched_containers.has(&"equipment"), "kept for re-saving")
	assert_eq(bag.count(&"wood"), 17)
	assert_eq(bag.get_stack(2).uid, "0123456789abcdef0123456789abcdef", "same cell")
	assert_eq(grid_map(bag), "w.S./..S./..S.")


func test_old_save_into_a_too_small_grid_overflows_instead_of_losing() -> void:
	var text := FileAccess.get_file_as_string("res://tests/inventory_kit/fixtures/save_v1.json")
	var bag := IKContainer.create_grid(&"bag", 2, 2, make_grid_db())
	var report := IKSerializer.load_into(JSON.parse_string(text), [bag])
	assert_true(report.ok)
	assert_eq(bag.count(&"wood"), 17)
	assert_eq(report.overflow.size(), 1, "the 1x3 sword fits nowhere in 2x2")
	var stack: IKItemStack = report.overflow[0]["stack"]
	assert_eq(stack.uid, "0123456789abcdef0123456789abcdef", "kept intact for the game to hand back")


func test_overlapping_entries_are_relocated() -> void:
	var bag := IKContainer.create_grid(&"bag", 3, 3, make_grid_db())
	var report := IKSerializer.load_into(_doc({"bag": {"size": 9, "slots": [
		{"i": 0, "id": "sword", "n": 1, "uid": "s1"},
		{"i": 3, "id": "gem", "n": 1},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(grid_map(bag), "Sg./S../S..")
	assert_eq(report.warnings.size(), 1)
	assert_true(report.warnings[0].contains("no longer fits at cell 3"), str(report.warnings))


func test_items_that_no_longer_fit_upright_are_turned() -> void:
	var bag := IKContainer.create_grid(&"bag", 3, 1, make_grid_db())
	var report := IKSerializer.load_into(_doc({"bag": {"size": 9, "slots": [
		{"i": 0, "id": "sword", "n": 1, "uid": "s1"},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(grid_map(bag), "SSS")
	assert_true(bag.get_stack(0).rotated)


func test_bad_or_impossible_rotation_flags_are_ignored() -> void:
	var bag := IKContainer.create_grid(&"bag", 2, 4, make_grid_db())
	var report := IKSerializer.load_into(_doc({"bag": {"size": 8, "slots": [
		{"i": 0, "id": "staff", "n": 1, "uid": "st", "rot": true},
		{"i": 1, "id": "wood", "n": 2, "rot": "yes"},
	]}}), [bag])
	assert_true(report.ok)
	assert_false(bag.get_stack(0).rotated, "the staff cannot turn")
	assert_false(bag.get_stack(1).rotated, "only true counts")
	assert_eq(grid_map(bag), "|w/|./|./|.")


func test_unknown_items_keep_their_cell() -> void:
	var bag := IKContainer.create_grid(&"bag", 3, 2, make_grid_db())
	var report := IKSerializer.load_into(_doc({"bag": {"size": 6, "slots": [
		{"i": 4, "id": "ghost", "n": 2},
		{"i": 0, "id": "plank", "n": 3},
	]}}), [bag])
	assert_true(report.ok)
	assert_eq(report.unknown_items, 1)
	assert_eq(bag.get_stack(4).item_id, &"ghost")
	assert_eq(bag.get_anchor(4), 4, "unknown items take one cell")
	var resaved := IKSerializer.container_to_dict(bag)
	assert_eq(resaved["slots"].size(), 2, "and survive the next save")


func test_grid_save_loads_into_classic_slots_and_back() -> void:
	var db := make_grid_db()
	var bag := _layout(db)
	var doc := IKSerializer.to_dict([bag])
	var classic := IKContainer.new(&"bag", 15, db)
	var report := IKSerializer.load_into(doc, [classic])
	assert_true(report.ok)
	assert_eq(report.warnings.size(), 0)
	assert_eq(classic.get_totals(), bag.get_totals())
	var again := IKContainer.create_grid(&"bag", 5, 3, db)
	assert_true(IKSerializer.load_into(IKSerializer.to_dict([classic]), [again]).ok)
	assert_eq(grid_map(again), "HH==w/HHSSS/.....", "positions and rotation survive the trip")


func test_classic_save_into_a_grid_repairs_collisions() -> void:
	var db := make_grid_db()
	var classic := IKContainer.new(&"bag", 4, db)
	assert_ok(classic.add(&"sword"))
	assert_ok(classic.add(&"helmet"))
	assert_ok(classic.add(&"wood", 4))
	var grid := IKContainer.create_grid(&"bag", 4, 3, db)
	var report := IKSerializer.load_into(IKSerializer.to_dict([classic]), [grid])
	assert_true(report.ok)
	assert_eq(report.overflow.size(), 0)
	assert_eq(grid.get_totals(), classic.get_totals())
	assert_eq(IKAudit.validate([grid]).size(), 0)
	assert_eq(grid_map(grid), "SHHw/SHH./S...")


func test_load_into_a_smaller_grid_overflow_keeps_totals() -> void:
	var db := make_grid_db()
	var bag := _layout(db)
	var small := IKContainer.create_grid(&"bag", 2, 2, db)
	var report := IKSerializer.load_into(IKSerializer.to_dict([bag]), [small])
	assert_true(report.ok)
	var totals := small.get_totals()
	for entry in report.overflow:
		var stack: IKItemStack = entry["stack"]
		totals[stack.item_id] = totals.get(stack.item_id, 0) + stack.amount
	assert_eq(totals, bag.get_totals(), "nothing destroyed")
	assert_eq(IKAudit.validate([small]).size(), 0)


func test_save_file_round_trip() -> void:
	var db := make_grid_db()
	var bag := _layout(db)
	var chest := IKContainer.new(&"chest", 4, db)
	assert_ok(chest.add(&"potion", 3))
	var save := IKSaveFile.new(DIR + "/grid.json")
	assert_eq(save.save([bag, chest]), OK)
	var bag2 := IKContainer.create_grid(&"bag", 5, 3, db)
	var chest2 := IKContainer.new(&"chest", 4, db)
	var report := save.load_into([bag2, chest2])
	assert_true(report.ok, str(report))
	assert_eq(bag2.to_debug_array(), bag.to_debug_array())
	assert_eq(chest2.count(&"potion"), 3)
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + file)
	DirAccess.remove_absolute(DIR)


func test_load_refreshes_cell_queries() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 5, 3, db)
	assert_eq(bag.get_free_slot_count(), 15)
	var changed := [false]
	bag.slots_changed.connect(func(_slots: PackedInt32Array) -> void: changed[0] = true)
	assert_true(IKSerializer.load_into(IKSerializer.to_dict([_layout(db)]), [bag]).ok)
	assert_true(changed[0])
	assert_eq(bag.get_free_slot_count(), 5)
	assert_eq(bag.get_anchor(9), 7)
	disconnect_all([bag])
