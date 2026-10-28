extends "res://tests/inventory_kit/ik_test_case.gd"
## Adding, removing, reading and resizing.


func test_add_tops_up_then_fills_empty_slots() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	assert_ok(bag.add(&"wood", 15))
	assert_ok(bag.add(&"wood", 10))
	assert_eq(bag.get_stack(0).amount, 20)
	assert_eq(bag.get_stack(1).amount, 5)
	assert_eq(bag.count(&"wood"), 25)


func test_add_fails_without_partial_and_changes_nothing() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	assert_ok(bag.add(&"potion", 8))
	var before := bag.to_debug_array()
	assert_code(bag.add(&"potion", 5), IKResult.Code.CONTAINER_FULL)
	assert_eq(bag.to_debug_array(), before)


func test_add_partial_reports_remainder() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	var result := bag.add(&"potion", 13, true)
	assert_ok(result)
	assert_eq(result.remainder, 3)
	assert_eq(bag.count(&"potion"), 10)


func test_add_unknown_item_fails() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	assert_code(bag.add(&"dragon"), IKResult.Code.UNKNOWN_ITEM)
	assert_code(bag.add(&"wood", 0), IKResult.Code.INVALID_ARGUMENT)


func test_unique_items_get_one_slot_and_a_uid_each() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	assert_ok(bag.add(&"sword", 3))
	assert_eq(bag.find_slots(&"sword").size(), 3)
	var uids := {}
	for slot in bag.find_slots(&"sword"):
		var stack := bag.get_stack(slot)
		assert_eq(stack.amount, 1)
		assert_true(stack.has_uid())
		uids[stack.uid] = true
	assert_eq(uids.size(), 3)


func test_add_stack_keeps_uid_and_data() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	assert_ok(bag.add_stack(IKItemStack.new(&"sword", 1, "fixed-uid", {"durability": 7})))
	var stack := bag.get_stack(0)
	assert_eq(stack.uid, "fixed-uid")
	assert_eq(stack.data["durability"], 7)
	assert_code(bag.add_stack(IKItemStack.new(&"sword", 1, "fixed-uid")), IKResult.Code.INVARIANT_VIOLATION,
		"same uid twice in one container")


func test_items_with_different_data_do_not_merge() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	assert_ok(bag.add(&"wood", 2))
	assert_ok(bag.add(&"wood", 2, false, {"wet": true}))
	assert_eq(bag.find_slots(&"wood").size(), 2)


func test_remove_takes_from_last_slots() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 45)
	assert_ok(bag.remove(&"wood", 10))
	assert_eq(bag.get_stack(0).amount, 20)
	assert_eq(bag.get_stack(1).amount, 15)
	assert_true(bag.is_slot_empty(2))


func test_remove_more_than_available_fails() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 5)
	assert_code(bag.remove(&"wood", 6), IKResult.Code.NOT_ENOUGH_ITEMS)
	assert_eq(bag.count(&"wood"), 5)


func test_remove_at() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"stone", 10)
	assert_ok(bag.remove_at(0, 4))
	assert_eq(bag.count(&"stone"), 6)
	assert_ok(bag.remove_at(0))
	assert_true(bag.is_slot_empty(0))
	assert_code(bag.remove_at(0), IKResult.Code.SLOT_EMPTY)
	assert_code(bag.remove_at(9), IKResult.Code.SLOT_OUT_OF_RANGE)


func test_try_consume_is_all_or_nothing() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	bag.add(&"wood", 5)
	bag.add(&"stone", 2)
	assert_code(bag.try_consume({&"wood": 4, &"stone": 3}), IKResult.Code.NOT_ENOUGH_ITEMS)
	assert_eq(bag.count(&"wood"), 5, "wood must not be consumed when stone is missing")
	assert_true(bag.has_all({&"wood": 4, &"stone": 2}))
	assert_ok(bag.try_consume({&"wood": 4, &"stone": 2}))
	assert_eq(bag.get_totals(), {&"wood": 1})


func test_returned_stacks_are_copies() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"wood", 5)
	var stack := bag.get_stack(0)
	stack.amount = 999
	assert_eq(bag.count(&"wood"), 5)


func test_resize() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"wood", 30)
	assert_ok(bag.resize(5))
	assert_eq(bag.size(), 5)
	assert_ok(bag.resize(2))
	assert_code(bag.resize(1), IKResult.Code.SLOT_OCCUPIED)
	assert_eq(bag.count(&"wood"), 30)


func test_container_without_database_rejects_items() -> void:
	var bag := IKContainer.new(&"bag", 2)
	assert_code(bag.add(&"wood"), IKResult.Code.UNKNOWN_ITEM)


func test_container_rule_filters_items() -> void:
	var db := make_db()
	var pouch := IKContainer.new(&"pouch", 3, db)
	pouch.rules.append(_OnlyCategory.new(&"consumable"))
	assert_code(pouch.add(&"wood"), IKResult.Code.CONTAINER_FULL, "no slot accepts wood")
	assert_ok(pouch.add(&"potion", 3))


func test_container_validate_slots_rule() -> void:
	var bag := IKContainer.new(&"bag", 5, make_db())
	bag.rules.append(_MaxTotal.new(10))
	assert_ok(bag.add(&"wood", 8))
	assert_code(bag.add(&"stone", 3), IKResult.Code.RULE_REJECTED)
	assert_eq(bag.count(&"stone"), 0)


class _OnlyCategory extends IKContainerRule:
	var category: StringName

	func _init(p_category: StringName) -> void:
		category = p_category

	func accepts(_stack: IKItemStack, definition: IKItemDefinition) -> bool:
		return definition.category == category


class _MaxTotal extends IKContainerRule:
	var limit: int

	func _init(p_limit: int) -> void:
		limit = p_limit

	func validate_slots(slots: Array, _database: IKItemDatabase) -> bool:
		var total := 0
		for stack in slots:
			if stack != null:
				total += stack.amount
		return total <= limit
