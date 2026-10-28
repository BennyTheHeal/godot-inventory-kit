extends "res://tests/inventory_kit/ik_test_case.gd"
## Move, merge, swap, split and quick transfer.


func test_move_to_empty_slot() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 10)
	assert_ok(bag.move(0, 2))
	assert_true(bag.is_slot_empty(0))
	assert_eq(bag.get_stack(2).amount, 10)


func test_move_part_of_a_stack() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 10)
	assert_ok(bag.move(0, 1, 4))
	assert_eq(bag.get_stack(0).amount, 6)
	assert_eq(bag.get_stack(1).amount, 4)


func test_move_merges_up_to_max_stack() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 20)
	bag.add(&"wood", 15)
	bag.remove_at(0, 8)
	assert_ok(bag.move(1, 0))
	assert_eq(bag.get_stack(0).amount, 20)
	assert_eq(bag.get_stack(1).amount, 7, "what does not fit stays in the source")


func test_move_onto_full_slot_reports_slot_full() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 25)
	assert_code(bag.move(1, 0), IKResult.Code.SLOT_FULL)


func test_move_swaps_different_items() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"wood", 3)
	bag.add(&"stone", 7)
	assert_ok(bag.move(0, 1))
	assert_eq(bag.get_stack(0).item_id, &"stone")
	assert_eq(bag.get_stack(1).item_id, &"wood")


func test_partial_drop_on_other_item_fails() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"wood", 3)
	bag.add(&"stone", 7)
	assert_code(bag.move(0, 1, 1), IKResult.Code.NOT_MERGEABLE)


func test_move_to_same_slot_is_a_no_op() -> void:
	var bag := IKContainer.new(&"bag", 2, make_db())
	bag.add(&"wood", 3)
	var revision := bag.get_revision()
	assert_ok(bag.move(0, 0))
	assert_eq(bag.get_stack(0).amount, 3)
	assert_eq(bag.get_revision(), revision + 1, "commit still runs")


func test_equipment_slot_rules() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	var equipment := make_equipment(db)
	bag.add(&"sword")
	bag.add(&"helmet")
	bag.add(&"potion", 3)
	assert_code(bag.move_to(0, equipment, 1), IKResult.Code.RULE_REJECTED, "sword in head slot")
	assert_ok(bag.move_to(0, equipment, 0))
	assert_ok(bag.move_to(1, equipment, 1))
	assert_ok(bag.move_to(2, equipment, 2, 2))
	assert_eq(equipment.get_stack(2).amount, 2)
	assert_eq(bag.count(&"potion"), 1)


func test_swap_checks_both_slot_rules() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 2, db)
	var equipment := make_equipment(db)
	bag.add(&"sword", 2)
	assert_ok(bag.move_to(0, equipment, 0))
	# Bag slot 1 holds a sword, equipment slot 0 a sword: swapping two swords is fine.
	assert_ok(equipment.move_to(0, bag, 1))
	bag.add(&"wood", 1)
	var wood_slot := bag.find_slots(&"wood")[0]
	assert_code(bag.move_to(wood_slot, equipment, 0), IKResult.Code.RULE_REJECTED)


func test_split() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"stone", 9)
	assert_ok(bag.split(0, 4))
	assert_eq(bag.get_stack(0).amount, 5)
	assert_eq(bag.get_stack(1).amount, 4)
	assert_ok(bag.split(0, 2, 2))
	assert_eq(bag.get_stack(2).amount, 2)
	assert_code(bag.split(0, 1), IKResult.Code.CONTAINER_FULL)


func test_split_invalid_cases() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"stone", 4)
	bag.add(&"sword")
	assert_code(bag.split(0, 4), IKResult.Code.INVALID_ARGUMENT, "split everything")
	assert_code(bag.split(0, 0), IKResult.Code.INVALID_ARGUMENT)
	assert_code(bag.split(1, 1), IKResult.Code.NOT_SPLITTABLE, "unique item")
	assert_code(bag.split(0, 1, 1), IKResult.Code.SLOT_OCCUPIED)
	assert_code(bag.split(2, 1), IKResult.Code.SLOT_EMPTY)


func test_transfer_merges_then_fills() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var chest := IKContainer.new(&"chest", 2, db)
	chest.add(&"wood", 18)
	bag.add(&"wood", 20)
	assert_ok(bag.transfer_to(0, chest))
	assert_eq(chest.get_stack(0).amount, 20)
	assert_eq(chest.get_stack(1).amount, 18)
	assert_true(bag.is_slot_empty(0))


func test_transfer_with_remainder() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 1, db)
	var chest := IKContainer.new(&"chest", 1, db)
	chest.add(&"wood", 15)
	bag.add(&"wood", 12)
	var result := bag.transfer_to(0, chest)
	assert_ok(result)
	assert_eq(result.remainder, 7)
	assert_eq(bag.count(&"wood"), 7)
	assert_eq(chest.count(&"wood"), 20)


func test_transfer_into_full_container_fails() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 1, db)
	var chest := IKContainer.new(&"chest", 1, db)
	chest.add(&"stone", 1)
	bag.add(&"wood", 3)
	assert_code(bag.transfer_to(0, chest), IKResult.Code.CONTAINER_FULL)
	assert_code(bag.transfer_to(0, bag), IKResult.Code.INVALID_ARGUMENT)


func test_unique_item_keeps_uid_across_containers() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 2, db)
	var chest := IKContainer.new(&"chest", 2, db)
	bag.add_stack(IKItemStack.new(&"sword", 1, "", {"durability": 3}))
	var uid := bag.get_stack(0).uid
	assert_ok(bag.transfer_to(0, chest))
	assert_eq(chest.get_stack(0).uid, uid)
	assert_eq(chest.get_stack(0).data["durability"], 3)
	assert_ok(chest.move_to(0, bag, 1))
	assert_eq(bag.get_stack(1).uid, uid)
