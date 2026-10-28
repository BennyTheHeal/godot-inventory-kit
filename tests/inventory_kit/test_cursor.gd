extends "res://tests/inventory_kit/ik_test_case.gd"
## The held stack: pick, place, half, one, swap, quick move, return.

var db: IKItemDatabase
var bag: IKContainer
var chest: IKContainer
var cursor: IKCursor


func _setup() -> void:
	db = make_db()
	bag = IKContainer.new(&"bag", 4, db)
	chest = IKContainer.new(&"chest", 4, db)
	cursor = IKCursor.new(db)


func _total() -> Dictionary:
	return IKAudit.totals([bag, chest, cursor.container])


func test_primary_picks_and_places() -> void:
	_setup()
	bag.add(&"wood", 10)
	assert_ok(cursor.primary(bag, 0))
	assert_true(cursor.is_holding())
	assert_true(bag.is_slot_empty(0))
	assert_eq(cursor.origin_container, bag)
	assert_ok(cursor.primary(chest, 2))
	assert_false(cursor.is_holding())
	assert_eq(chest.get_stack(2).amount, 10)
	assert_eq(cursor.origin_container, null)


func test_primary_on_empty_slot_with_empty_hand_does_nothing() -> void:
	_setup()
	assert_ok(cursor.primary(bag, 0))
	assert_false(cursor.is_holding())


func test_place_merges_and_keeps_the_rest() -> void:
	_setup()
	bag.add(&"wood", 20)
	bag.add(&"wood", 15)
	cursor.primary(bag, 1)
	bag.remove_at(0, 5)
	assert_ok(cursor.primary(bag, 0))
	assert_eq(bag.get_stack(0).amount, 20)
	assert_eq(cursor.get_held().amount, 10, "what does not fit stays in hand")


func test_place_on_other_item_swaps() -> void:
	_setup()
	bag.add(&"wood", 3)
	bag.add(&"stone", 7)
	cursor.primary(bag, 0)
	assert_ok(cursor.primary(bag, 1))
	assert_eq(bag.get_stack(1).item_id, &"wood")
	assert_eq(cursor.get_held().item_id, &"stone")
	assert_eq(cursor.origin_slot, 1, "origin follows the swapped item")


func test_secondary_takes_half_rounded_up() -> void:
	_setup()
	bag.add(&"stone", 7)
	assert_ok(cursor.secondary(bag, 0))
	assert_eq(cursor.get_held().amount, 4)
	assert_eq(bag.get_stack(0).amount, 3)


func test_secondary_places_one() -> void:
	_setup()
	bag.add(&"stone", 5)
	cursor.primary(bag, 0)
	assert_ok(cursor.secondary(bag, 1))
	assert_ok(cursor.secondary(bag, 1))
	assert_ok(cursor.secondary(bag, 0))
	assert_eq(bag.get_stack(1).amount, 2)
	assert_eq(bag.get_stack(0).amount, 1)
	assert_eq(cursor.get_held().amount, 2)


func test_secondary_on_other_item_is_refused() -> void:
	_setup()
	bag.add(&"stone", 5)
	bag.add(&"wood", 5)
	cursor.primary(bag, 0)
	assert_code(cursor.secondary(bag, 1), IKResult.Code.NOT_MERGEABLE)
	assert_eq(_total(), {&"stone": 5, &"wood": 5})


func test_rules_apply_to_the_hand() -> void:
	_setup()
	var equipment := make_equipment(db)
	bag.add(&"wood", 2)
	cursor.primary(bag, 0)
	assert_code(cursor.primary(equipment, 0), IKResult.Code.RULE_REJECTED)
	assert_true(cursor.is_holding())


func test_quick_move_needs_an_empty_hand() -> void:
	_setup()
	bag.add(&"wood", 5)
	bag.add(&"stone", 5)
	assert_ok(cursor.quick_move(bag, 0, chest))
	assert_eq(chest.count(&"wood"), 5)
	cursor.primary(bag, 1)
	assert_code(cursor.quick_move(bag, 1, chest), IKResult.Code.SLOT_OCCUPIED)


func test_return_held_to_origin_slot() -> void:
	_setup()
	bag.add(&"wood", 5)
	cursor.secondary(bag, 0)
	assert_ok(cursor.return_held())
	assert_eq(bag.get_stack(0).amount, 5)
	assert_false(cursor.is_holding())


func test_return_held_when_origin_slot_was_taken() -> void:
	_setup()
	bag.add(&"wood", 5)
	cursor.primary(bag, 0)
	bag.add(&"stone", 1)  # lands in slot 0
	assert_ok(cursor.return_held())
	assert_eq(bag.get_stack(0).item_id, &"stone", "no swap on return")
	assert_eq(bag.count(&"wood"), 5)


func test_return_held_uses_fallbacks_then_fails_safely() -> void:
	_setup()
	var small := IKContainer.new(&"small", 1, db)
	small.add(&"wood", 3)
	cursor.primary(small, 0)
	small.add(&"gem")
	assert_ok(cursor.return_held([chest]))
	assert_eq(chest.count(&"wood"), 3)
	small.remove(&"gem")
	small.add(&"wood", 2)
	cursor.primary(small, 0)
	small.add(&"gem")
	assert_code(cursor.return_held(), IKResult.Code.CONTAINER_FULL)
	assert_eq(cursor.get_held().amount, 2, "items stay in hand rather than vanish")


func test_take_held_removes_the_stack() -> void:
	_setup()
	bag.add_stack(IKItemStack.new(&"sword", 1, "", {"durability": 4}))
	cursor.primary(bag, 0)
	var taken := cursor.take_held()
	assert_eq(taken.data["durability"], 4)
	assert_false(cursor.is_holding())
	assert_eq(_total(), {})


func test_held_items_are_saved_like_any_container() -> void:
	_setup()
	bag.add(&"wood", 6)
	cursor.secondary(bag, 0)
	var doc := IKSerializer.to_dict([bag, cursor.container])
	var restored_bag := IKContainer.new(&"bag", 4, db)
	var restored_cursor := IKCursor.new(db)
	assert_true(IKSerializer.load_into(doc, [restored_bag, restored_cursor.container]).ok)
	assert_eq(restored_cursor.get_held().amount, 3)
