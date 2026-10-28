extends "res://tests/inventory_kit/ik_test_case.gd"
## Atomicity, poisoning, staleness and signal timing.


func test_failed_transaction_changes_nothing() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var chest := IKContainer.new(&"chest", 3, db)
	bag.add(&"wood", 10)
	chest.add(&"stone", 5)
	var bag_before := bag.to_debug_array()
	var chest_before := chest.to_debug_array()
	var result := IKTransaction.new() \
		.move(bag, 0, chest, 1) \
		.remove(chest, &"stone", 2) \
		.remove(chest, &"gem", 1) \
		.commit()
	assert_code(result, IKResult.Code.NOT_ENOUGH_ITEMS)
	assert_eq(bag.to_debug_array(), bag_before)
	assert_eq(chest.to_debug_array(), chest_before)


func test_successful_multi_container_transaction() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var chest := IKContainer.new(&"chest", 3, db)
	bag.add(&"wood", 10)
	var result := IKTransaction.new() \
		.consume(bag, {&"wood": 4}) \
		.add(chest, &"potion", 1) \
		.move(bag, 0, chest, 2, 3) \
		.commit()
	assert_ok(result)
	assert_eq(bag.count(&"wood"), 3)
	assert_eq(chest.count(&"wood"), 3)
	assert_eq(chest.count(&"potion"), 1)


func test_operations_after_a_failure_are_ignored() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	var tx := IKTransaction.new()
	tx.remove(bag, &"wood", 1)
	assert_true(tx.has_failed())
	tx.add(bag, &"wood", 5)
	assert_code(tx.commit(), IKResult.Code.NOT_ENOUGH_ITEMS)
	assert_eq(bag.count(&"wood"), 0)


func test_commit_twice_fails() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	var tx := IKTransaction.new().add(bag, &"wood", 1)
	assert_ok(tx.commit())
	assert_code(tx.commit(), IKResult.Code.TRANSACTION_CLOSED)
	assert_eq(bag.count(&"wood"), 1)


func test_stale_transaction_is_rejected() -> void:
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 5)
	var tx := IKTransaction.new().move(bag, 0, bag, 1)
	bag.add(&"wood", 1)
	assert_code(tx.commit(), IKResult.Code.CONCURRENT_MODIFICATION)
	assert_eq(bag.get_stack(0).amount, 6)


func test_empty_transaction_succeeds() -> void:
	assert_ok(IKTransaction.new().commit())


func test_signals_fire_after_commit_with_final_state() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var chest := IKContainer.new(&"chest", 3, db)
	bag.add(&"wood", 10)
	var events := []
	bag.item_removed.connect(func(id: StringName, n: int) -> void:
		events.append(["bag-", id, n, bag.count(&"wood"), chest.count(&"wood")]))
	chest.item_added.connect(func(id: StringName, n: int) -> void:
		events.append(["chest+", id, n, bag.count(&"wood"), chest.count(&"wood")]))
	assert_ok(bag.move_to(0, chest, 0, 4))
	assert_eq(events,[["bag-", &"wood", 4, 6, 4], ["chest+", &"wood", 4, 6, 4]],
		"both containers already updated when the first signal fires")
	disconnect_all([bag, chest])


func test_slots_changed_lists_only_changed_slots() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	bag.add(&"wood", 5)
	bag.add(&"stone", 5)
	var received := []
	bag.slots_changed.connect(func(slots: PackedInt32Array) -> void: received.append(slots))
	bag.move(1, 3)
	assert_eq(received, [PackedInt32Array([1, 3])])
	disconnect_all([bag])


func test_internal_move_emits_no_add_or_remove() -> void:
	var bag := IKContainer.new(&"bag", 4, make_db())
	bag.add(&"wood", 5)
	var count := [0]
	bag.item_added.connect(func(_id: StringName, _n: int) -> void: count[0] += 1)
	bag.item_removed.connect(func(_id: StringName, _n: int) -> void: count[0] += 1)
	bag.move(0, 2)
	bag.split(2, 2)
	assert_eq(count[0], 0)
	disconnect_all([bag])


func test_failed_commit_emits_nothing() -> void:
	var bag := IKContainer.new(&"bag", 1, make_db())
	var fired := [false]
	bag.changed.connect(func() -> void: fired[0] = true)
	bag.add(&"wood", 999)
	assert_false(fired[0])
	disconnect_all([bag])


func test_listener_can_start_a_new_transaction() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 3, db)
	var rewards := IKContainer.new(&"rewards", 3, db)
	bag.item_added.connect(func(id: StringName, n: int) -> void:
		if id == &"wood":
			rewards.add(&"stone", n))
	assert_ok(bag.add(&"wood", 3))
	assert_eq(rewards.count(&"stone"), 3)
	assert_ok(bag.add(&"wood", 2))
	assert_eq(rewards.count(&"stone"), 5)
	disconnect_all([bag])


func test_broken_rule_cannot_corrupt_via_working_copy() -> void:
	# A rule that rejects everything at validation time must leave state intact.
	var bag := IKContainer.new(&"bag", 3, make_db())
	bag.add(&"wood", 3)
	bag.rules.append(_RejectAll.new())
	assert_code(bag.move(0, 1), IKResult.Code.RULE_REJECTED)
	assert_eq(bag.get_stack(0).amount, 3)


class _RejectAll extends IKContainerRule:
	func validate_slots(_slots: Array, _database: IKItemDatabase) -> bool:
		return false


func test_operation_cost_does_not_grow_with_container_size() -> void:
	var db := make_db()
	var big := IKContainer.new(&"big", 2000, db)
	for i in 1500:
		big.add(&"stone" if i % 2 == 0 else &"wood", 1 + i % 3)
	var start := Time.get_ticks_msec()
	for i in 300:
		big.move(i % 1500, (i * 7 + 3) % 2000)
	var elapsed := Time.get_ticks_msec() - start
	assert_true(elapsed < 1500, "300 moves in a 2000-slot container took %d ms" % elapsed)
	assert_eq(IKAudit.validate([big]).size(), 0, "still consistent")


func test_failed_transaction_never_touches_shared_stacks() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add(&"wood", 10)
	bag.add(&"stone", 5)
	var before := bag.to_debug_array()
	var result := IKTransaction.new().remove(bag, &"wood", 4).move(bag, 1, bag, 2, 2).remove(bag, &"gem", 1).commit()
	assert_code(result, IKResult.Code.NOT_ENOUGH_ITEMS)
	assert_eq(bag.to_debug_array(), before, "modified stacks were private copies")


func test_set_data_changes_one_copy() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add_stack(IKItemStack.new(&"sword", 1, "s1", {"durability": 10, "gems": ["ruby"]}))
	bag.add_stack(IKItemStack.new(&"sword", 1, "s2", {"durability": 10}))
	var changed: Array = []
	bag.slots_changed.connect(func(slots: PackedInt32Array) -> void: changed.append(slots))
	assert_ok(bag.set_data(0, {"durability": 9, "gems": null, "sharpened": true}))
	assert_eq(bag.get_stack(0).data, {"durability": 9, "sharpened": true})
	assert_eq(bag.get_stack(0).uid, "s1", "same copy")
	assert_eq(bag.get_stack(1).data, {"durability": 10}, "the other sword is untouched")
	assert_eq(changed, [PackedInt32Array([0])])
	assert_code(bag.set_data(2, {"durability": 1}), IKResult.Code.SLOT_EMPTY)
	assert_code(bag.set_data(9, {"durability": 1}), IKResult.Code.SLOT_OUT_OF_RANGE)
	var result := IKTransaction.new().set_data(bag, 0, {"durability": 0}).remove(bag, &"gem", 1).commit()
	assert_false(result.ok)
	assert_eq(bag.get_stack(0).data.durability, 9, "all or nothing")
	disconnect_all([bag])


func test_stacks_with_different_data_stop_merging() -> void:
	var db := make_db()
	var bag := IKContainer.new(&"bag", 4, db)
	bag.add(&"potion", 4)
	assert_ok(bag.set_data(0, {"blessed": true}))
	bag.add(&"potion", 1)
	assert_eq(bag.get_stack(0).amount, 4)
	assert_eq(bag.get_stack(1).amount, 1, "a plain potion does not join blessed ones")
