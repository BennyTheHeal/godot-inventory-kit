extends "res://tests/inventory_kit/ik_test_case.gd"
## Item definitions, database and stacks.


func test_database_lookup() -> void:
	var db := make_db()
	assert_true(db.has_item(&"wood"))
	assert_eq(db.get_item(&"potion").max_stack, 5)
	assert_eq(db.get_item(&"nothing"), null)
	assert_eq(db.get_ids().size(), 6)


func test_database_sees_items_appended_directly() -> void:
	var db := make_db()
	db.items.append(make_item(&"rope", 10))
	assert_true(db.has_item(&"rope"), "index should rebuild when the array grows")


func test_database_validate_reports_problems() -> void:
	var db := IKItemDatabase.new()
	db.add_item(make_item(&"wood", 20))
	db.add_item(make_item(&"wood", 10))
	db.add_item(make_item(&"", 1))
	db.add_item(null)
	db.add_item(make_item(&"ring", 5, true))
	var issues := db.validate()
	assert_eq(issues.size(), 4, "duplicate + empty id + null + unique with max_stack")
	assert_eq(db.get_item(&"wood").max_stack, 20, "first definition wins")


func test_valid_database_has_no_issues() -> void:
	assert_eq(make_db().validate().size(), 0)


func test_unique_items_never_stack() -> void:
	var sword := make_item(&"sword", 99, true)
	assert_eq(sword.get_effective_max_stack(), 1)


func test_stack_copy_is_deep() -> void:
	var stack := IKItemStack.new(&"sword", 1, "abc", {"durability": 10, "mods": [1, 2]})
	var copy := stack.copy()
	copy.data["durability"] = 1
	copy.data["mods"].append(3)
	assert_eq(stack.data["durability"], 10)
	assert_eq(stack.data["mods"].size(), 2)


func test_stack_merge_rules() -> void:
	var a := IKItemStack.new(&"wood", 3)
	assert_true(a.can_merge_with(IKItemStack.new(&"wood", 5)))
	assert_false(a.can_merge_with(IKItemStack.new(&"stone", 5)), "different item")
	assert_false(a.can_merge_with(IKItemStack.new(&"wood", 1, "uid")), "uid stack")
	assert_false(a.can_merge_with(IKItemStack.new(&"wood", 1, "", {"wet": true})), "different data")
	var wet := IKItemStack.new(&"wood", 1, "", {"wet": true})
	assert_true(wet.can_merge_with(IKItemStack.new(&"wood", 2, "", {"wet": true})), "equal data merges")


func test_uids_are_unique() -> void:
	var seen := {}
	for i in 1000:
		var uid := IKUid.generate()
		assert_eq(uid.length(), 32)
		assert_false(seen.has(uid), "uid collision")
		seen[uid] = true
