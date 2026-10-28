extends "res://tests/inventory_kit/ik_test_case.gd"
## Grid containers: multi-cell items, placement, rotation, moves, swaps, splits.
## Layouts are checked with grid_map(): one letter per cell, rows separated by "/"
## (S sword 1x3, H helmet 2x2, = plank 2x1, A armor 2x3, | staff 1x4, C crate 2x2).

const FIT_TEXT := "It does not fit there."


func _grid(width: int, height: int) -> IKContainer:
	return IKContainer.create_grid(&"grid", width, height, make_grid_db())


func _put(container: IKContainer, item_id: StringName, slot: int, amount: int = 1) -> void:
	var holder := IKContainer.new(&"holder", 1, container.database)
	assert_ok(holder.add(item_id, amount), "fixture add %s" % item_id)
	assert_ok(holder.move_to(0, container, slot), "fixture put %s at %d" % [item_id, slot])


func _assert_valid(containers: Array) -> void:
	var issues := IKAudit.validate(containers)
	assert_eq(issues.size(), 0, "audit: %s" % issues)


# --- Definitions and stacks -------------------------------------------------------

func test_definition_grid_size_defaults_and_rotation() -> void:
	var item := IKItemDefinition.new()
	assert_eq(item.grid_size, Vector2i.ONE, "one cell by default")
	assert_eq(item.get_grid_size(true), Vector2i.ONE)
	assert_false(item.is_rotatable(), "a square never needs turning")
	item.grid_size = Vector2i(1, 3)
	assert_eq(item.get_grid_size(), Vector2i(1, 3))
	assert_eq(item.get_grid_size(true), Vector2i(3, 1))
	assert_true(item.is_rotatable())
	item.can_rotate = false
	assert_eq(item.get_grid_size(true), Vector2i(1, 3), "can_rotate off: never turned")
	assert_false(item.is_rotatable())
	item.grid_size = Vector2i(0, -2)
	assert_eq(item.get_grid_size(), Vector2i.ONE, "sizes below 1 are clamped")


func test_stack_rotation_is_copied_compared_but_not_a_merge_barrier() -> void:
	var stack := IKItemStack.new(&"plank", 3)
	stack.rotated = true
	assert_true(stack.copy().rotated, "copy keeps the rotation")
	var flat := IKItemStack.new(&"plank", 3)
	assert_false(IKItemStack.same(stack, flat), "rotation is part of the value")
	assert_true(stack.can_merge_with(flat), "rotation never prevents stacking")
	assert_eq(stack.to_debug_dict().get("rot"), true)
	assert_false(flat.to_debug_dict().has("rot"), "debug dicts of unturned stacks are unchanged")


func test_classic_containers_ignore_grid_sizes() -> void:
	var bag := IKContainer.new(&"bag", 3, make_grid_db())
	assert_false(bag.is_grid())
	assert_ok(bag.add(&"armor", 3))
	assert_eq(bag.find_slots(&"armor").size(), 3, "one slot each, whatever the grid size")
	assert_eq(bag.get_item_size(0), Vector2i.ONE)
	assert_eq(bag.get_grid_width(), 0)
	assert_eq(bag.get_grid_height(), 0)


# --- Geometry and queries ---------------------------------------------------------

func test_create_grid_and_cell_coordinates() -> void:
	var bag := _grid(4, 3)
	assert_true(bag.is_grid())
	assert_eq(bag.size(), 12)
	assert_eq(bag.get_grid_width(), 4)
	assert_eq(bag.get_grid_height(), 3)
	assert_eq(bag.cell_of(6), Vector2i(2, 1))
	assert_eq(bag.slot_of(Vector2i(3, 2)), 11)
	assert_eq(bag.slot_of(Vector2i(4, 0)), -1, "right of the grid")
	assert_eq(bag.slot_of(Vector2i(0, 3)), -1, "below the grid")
	assert_eq(bag.slot_of(Vector2i(-1, 0)), -1)
	assert_eq(grid_map(bag), "..../..../....")


func test_constructor_grid_width_argument() -> void:
	var bag := IKContainer.new(&"bag", 6, make_grid_db(), 3)
	assert_true(bag.is_grid())
	assert_eq(bag.get_grid_height(), 2)


func test_covered_cells_report_their_item() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	assert_eq(grid_map(bag), "S.../S.../S...")
	assert_eq(bag.get_anchor(0), 0)
	assert_eq(bag.get_anchor(4), 0)
	assert_eq(bag.get_anchor(8), 0)
	assert_eq(bag.get_anchor(1), -1)
	assert_eq(bag.get_anchor(99), -1)
	assert_eq(bag.get_footprint(8), PackedInt32Array([0, 4, 8]))
	assert_eq(bag.get_footprint(1), PackedInt32Array())
	assert_false(bag.is_slot_empty(4), "a covered cell is not empty")
	assert_true(bag.is_slot_empty(1))
	assert_eq(bag.get_stack(4), null, "only the anchor holds the stack")
	assert_eq(bag.get_item_size(0), Vector2i(1, 3))
	assert_eq(bag.get_free_slot_count(), 9)
	assert_eq(bag.get_first_free_slot(), 1)


func test_placement_queries() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	var sword := bag.get_stack(0)
	var helmet := IKItemStack.new(&"helmet", 1, "h1")
	assert_true(bag.can_place(1, sword))
	assert_false(bag.can_place(0, sword), "its own cells are taken")
	assert_true(bag.can_place(0, sword, 0), "unless it is the item being moved")
	assert_false(bag.can_place(5, sword), "would stick out at the bottom")
	assert_false(bag.can_place(3, helmet), "would stick out on the right")
	assert_eq(bag.get_overlapping(0, helmet), PackedInt32Array([0]))
	assert_true(bag.can_drop(0, helmet), "one item under it: a swap")
	assert_false(bag.can_drop(3, helmet), "out of the grid")
	assert_eq(bag.find_place(helmet), {"slot": 1, "rotated": false})
	assert_false(bag.can_place(1, IKItemStack.new(&"dragon")), "unknown item")
	assert_false(bag.can_place(1, null))


# --- Adding (automatic placement) ---------------------------------------------------

func test_add_uses_first_free_place_row_by_row() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"armor"))
	assert_ok(bag.add(&"helmet"))
	assert_eq(grid_map(bag), "AAHH/AAHH/AA..")
	var before := bag.to_debug_array()
	assert_code(bag.add(&"sword"), IKResult.Code.CONTAINER_FULL, "1x3 fits neither upright nor turned")
	assert_eq(bag.to_debug_array(), before, "a refused add changes nothing")
	assert_ok(bag.add(&"wood", 25))
	assert_eq(grid_map(bag), "AAHH/AAHH/AAww")
	assert_eq(bag.get_stack(10).amount, 20)
	assert_eq(bag.get_stack(11).amount, 5)
	_assert_valid([bag])


func test_add_turns_items_that_only_fit_turned() -> void:
	var bag := _grid(3, 2)
	assert_ok(bag.add(&"sword"))
	assert_eq(grid_map(bag), "SSS/...")
	assert_true(bag.get_stack(0).rotated)
	assert_eq(bag.get_item_size(0), Vector2i(3, 1))
	assert_code(bag.add(&"staff"), IKResult.Code.CONTAINER_FULL, "staff (1x4, cannot turn) never fits")


func test_add_tops_up_existing_stacks_first() -> void:
	var bag := _grid(4, 2)
	assert_ok(bag.add(&"plank", 6))
	assert_ok(bag.add(&"plank", 7))
	assert_eq(bag.get_stack(0).amount, 10)
	assert_eq(bag.get_stack(2).amount, 3)
	assert_eq(grid_map(bag), "====/....")


func test_add_partial_reports_what_did_not_fit() -> void:
	var bag := _grid(2, 2)
	var result := bag.add(&"helmet", 3, true)
	assert_ok(result)
	assert_eq(result.remainder, 2)
	assert_eq(bag.count(&"helmet"), 1)
	assert_code(bag.add(&"helmet"), IKResult.Code.CONTAINER_FULL)


func test_unique_items_get_their_own_cells_and_uids() -> void:
	var bag := _grid(2, 3)
	assert_ok(bag.add(&"sword", 2))
	assert_eq(grid_map(bag), "SS/SS/SS")
	assert_true(bag.get_stack(0).uid != bag.get_stack(1).uid)
	var holder := IKContainer.new(&"holder", 1, bag.database)
	assert_ok(bag.remove_at(1))
	assert_ok(bag.add_stack(IKItemStack.new(&"sword", 1, "fixed")))
	assert_eq(bag.get_stack(1).uid, "fixed")
	assert_ok(holder.add_stack(IKItemStack.new(&"gem", 1)))
	assert_code(bag.add_stack(IKItemStack.new(&"sword", 1, "fixed")), IKResult.Code.CONTAINER_FULL)


func test_add_stack_keeps_its_rotation_when_it_fits() -> void:
	var bag := _grid(3, 3)
	var turned := IKItemStack.new(&"sword", 1, "s1")
	turned.rotated = true
	assert_ok(bag.add_stack(turned))
	assert_eq(grid_map(bag), "SSS/.../...")


func test_add_signals_net_amounts() -> void:
	var bag := _grid(4, 3)
	var added := []
	bag.item_added.connect(func(item_id: StringName, amount: int) -> void: added.append([item_id, amount]))
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.move(0, 2))
	assert_eq(added, [[&"sword", 1]], "moving inside the grid adds nothing")
	disconnect_all([bag])


# --- Moving -----------------------------------------------------------------------------

func test_move_to_free_cells_and_from_any_covered_cell() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.move(0, 3))
	assert_eq(grid_map(bag), "...S/...S/...S")
	assert_ok(bag.move(7, 1), "picking a covered cell moves the whole item")
	assert_eq(grid_map(bag), ".S../.S../.S..")
	_assert_valid([bag])


func test_move_may_overlap_its_own_old_cells() -> void:
	var bag := _grid(4, 1)
	assert_ok(bag.add(&"plank", 5))
	assert_ok(bag.move(0, 1))
	assert_eq(grid_map(bag), ".==.")
	assert_ok(bag.move(2, 2), "covered cell to the next cell: one step right")
	assert_eq(grid_map(bag), "..==")


func test_move_out_of_the_grid_fails_with_a_player_text() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	var before := bag.to_debug_array()
	var result := bag.move(0, 4)
	assert_code(result, IKResult.Code.SLOT_OUT_OF_RANGE)
	assert_eq(result.player_text, FIT_TEXT)
	assert_eq(IKText.result_message(result), FIT_TEXT)
	assert_eq(bag.to_debug_array(), before)
	assert_code(bag.move(0, 12), IKResult.Code.SLOT_OUT_OF_RANGE, "no such cell")


func test_move_over_two_items_is_refused() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.add(&"potion"))
	assert_ok(bag.add(&"gem"))
	assert_ok(bag.move(2, 5))
	assert_eq(grid_map(bag), "Sp../Sg../S...")
	var before := bag.to_debug_array()
	var result := bag.move(0, 1)
	assert_code(result, IKResult.Code.SLOT_OCCUPIED)
	assert_eq(result.player_text, FIT_TEXT)
	assert_eq(bag.to_debug_array(), before)


func test_swap_inside_the_grid() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	_put(bag, &"helmet", 2)
	assert_eq(grid_map(bag), "S.HH/S.HH/S...")
	assert_ok(bag.move(0, 2), "sword dropped on the helmet: they swap")
	assert_eq(grid_map(bag), "HHS./HHS./..S.")
	_assert_valid([bag])


func test_swap_without_room_changes_nothing() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	_put(bag, &"helmet", 1)
	assert_eq(grid_map(bag), "SHH./SHH./S...")
	var before := bag.to_debug_array()
	var result := bag.move(1, 0)
	assert_code(result, IKResult.Code.SLOT_OCCUPIED, "the sword cannot go where the helmet now is")
	assert_eq(result.player_text, FIT_TEXT)
	assert_eq(bag.to_debug_array(), before)


func test_dropping_on_the_same_item_merges() -> void:
	var bag := _grid(4, 2)
	assert_ok(bag.add(&"plank", 13))
	assert_ok(bag.remove_at(0, 4))
	assert_eq(bag.get_stack(0).amount, 6)
	assert_ok(bag.move(2, 1), "plank at cell 2 dropped over the plank at 0")
	assert_eq(bag.get_stack(0).amount, 9)
	assert_eq(bag.get_stack(2), null)
	assert_eq(bag.count(&"plank"), 9)
	assert_eq(grid_map(bag), "==../....")


func test_partial_moves() -> void:
	var bag := _grid(4, 2)
	assert_ok(bag.add(&"wood", 10))
	assert_ok(bag.move(0, 5, 4))
	assert_eq(bag.get_stack(0).amount, 6)
	assert_eq(bag.get_stack(5).amount, 4)
	assert_ok(bag.add(&"gem"))
	var gem_slot := bag.find_slots(&"gem")[0]
	assert_code(bag.move(0, gem_slot, 3), IKResult.Code.NOT_MERGEABLE, "part of a stack cannot swap")
	var planks := _grid(4, 1)
	assert_ok(planks.add(&"plank", 6))
	var before := planks.to_debug_array()
	assert_ok(planks.move(0, 1, 2), "part of a stack dropped on itself: nothing happens")
	assert_eq(planks.to_debug_array(), before)
	assert_code(bag.move(0, 1, 0), IKResult.Code.INVALID_ARGUMENT)
	assert_code(bag.move(0, 1, 99), IKResult.Code.INVALID_ARGUMENT)


func test_full_stack_merge_is_refused() -> void:
	var bag := _grid(4, 1)
	assert_ok(bag.add(&"plank", 20))
	assert_code(bag.move(2, 1), IKResult.Code.SLOT_FULL)


func test_moves_between_grid_and_classic_containers() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 3, 3, db)
	var chest := IKContainer.new(&"chest", 4, db)
	assert_ok(chest.add(&"sword"))
	assert_ok(chest.move_to(0, bag, 0))
	assert_eq(grid_map(bag), "S../S../S..")
	assert_ok(bag.move_to(3, chest, 2), "from a covered cell")
	assert_eq(chest.get_stack(2).item_id, &"sword")
	assert_eq(grid_map(bag), ".../.../...")
	_assert_valid([bag, chest])


func test_transfer_into_a_grid_places_and_turns() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 3, 1, db)
	var chest := IKContainer.new(&"chest", 4, db)
	assert_ok(chest.add(&"sword"))
	assert_ok(chest.transfer_to(0, bag))
	assert_eq(grid_map(bag), "SSS")
	assert_true(bag.get_stack(0).rotated)
	assert_ok(bag.transfer_to(1, chest), "back out from a covered cell")
	assert_eq(chest.count(&"sword"), 1)


func test_transfer_into_a_grid_reports_the_remainder() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 2, 1, db)
	var chest := IKContainer.new(&"chest", 4, db)
	assert_ok(bag.add(&"plank", 7))
	assert_ok(chest.add(&"plank", 10))
	var result := chest.transfer_to(0, bag)
	assert_ok(result)
	assert_eq(result.remainder, 7)
	assert_eq(bag.get_stack(0).amount, 10)
	assert_eq(chest.get_stack(0).amount, 7)
	assert_code(chest.transfer_to(0, bag), IKResult.Code.CONTAINER_FULL)


func test_swap_between_a_classic_slot_and_a_grid() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 3, 3, db)
	var chest := IKContainer.new(&"chest", 2, db)
	assert_ok(bag.add(&"sword"))
	assert_ok(chest.add(&"gem"))
	assert_ok(chest.move_to(0, bag, 3), "gem dropped on the sword: the sword goes to the chest slot")
	assert_eq(chest.get_stack(0).item_id, &"sword")
	assert_eq(grid_map(bag), ".../g../...")
	_assert_valid([bag, chest])


func test_swap_into_a_grid_without_room_is_refused() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 3, 3, db)
	var chest := IKContainer.new(&"chest", 1, db)
	assert_ok(bag.add(&"gem"))
	assert_ok(bag.add(&"potion"))
	assert_ok(bag.move(1, 3))
	assert_ok(chest.add(&"sword"))
	var before := bag.to_debug_array()
	var result := bag.move_to(0, chest, 0)
	assert_code(result, IKResult.Code.SLOT_OCCUPIED, "the sword would cover the potion")
	assert_eq(result.player_text, FIT_TEXT)
	assert_eq(bag.to_debug_array(), before)
	assert_eq(chest.get_stack(0).item_id, &"sword")


func test_rules_still_apply_in_grids() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 3, 3, db)
	var only_materials := IKTagSlotRule.new()
	only_materials.categories = [&"material"]
	assert_ok(bag.set_slot_rule(0, only_materials))
	assert_ok(bag.add(&"gem"))
	assert_eq(bag.get_anchor(0), -1, "automatic placement skips the cell the rule refuses")
	assert_code(bag.move(bag.find_slots(&"gem")[0], 0), IKResult.Code.RULE_REJECTED)


# --- Rotation -----------------------------------------------------------------------------

func test_rotate_in_place() -> void:
	var bag := _grid(3, 3)
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.rotate(3), "from a covered cell")
	assert_eq(grid_map(bag), "SSS/.../...")
	assert_ok(bag.rotate(0))
	assert_eq(grid_map(bag), "S../S../S..")
	assert_eq(bag.count(&"sword"), 1)


func test_rotate_without_room_is_refused() -> void:
	var bag := _grid(3, 3)
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.add(&"gem"))
	var before := bag.to_debug_array()
	var result := bag.rotate(0)
	assert_code(result, IKResult.Code.SLOT_OCCUPIED)
	assert_eq(result.player_text, FIT_TEXT)
	assert_eq(bag.to_debug_array(), before)
	var edge := _grid(3, 3)
	_put(edge, &"sword", 2)
	assert_code(edge.rotate(2), IKResult.Code.SLOT_OCCUPIED, "turning would stick out on the right")


func test_rotate_square_and_fixed_items() -> void:
	var bag := _grid(4, 4)
	assert_ok(bag.add(&"helmet"))
	assert_ok(bag.rotate(0), "a square turns without changing anything")
	assert_false(bag.get_stack(0).rotated)
	assert_ok(bag.add(&"staff"))
	var staff := bag.find_slots(&"staff")[0]
	var result := bag.rotate(staff)
	assert_code(result, IKResult.Code.INVALID_ARGUMENT)
	assert_eq(IKText.result_message(result), "This item cannot be turned.")
	assert_code(bag.rotate(15), IKResult.Code.SLOT_EMPTY)
	assert_code(bag.rotate(16), IKResult.Code.SLOT_OUT_OF_RANGE)


func test_rotate_in_a_classic_container_only_flips_the_flag() -> void:
	var holder := IKContainer.new(&"hand", 1, make_grid_db())
	assert_ok(holder.add(&"sword"))
	assert_ok(holder.rotate(0))
	assert_true(holder.get_stack(0).rotated)


# --- Split, remove, data ----------------------------------------------------------------

func test_split_finds_a_place_and_turns_if_needed() -> void:
	var bag := _grid(3, 2)
	assert_ok(bag.add(&"plank", 10))
	assert_ok(bag.split(0, 4))
	assert_eq(grid_map(bag), "==./==.")
	assert_eq(bag.get_stack(3).amount, 4)
	assert_ok(bag.split(1, 2), "from a covered cell; only a turned plank fits now")
	assert_eq(grid_map(bag), "===/===")
	assert_true(bag.get_stack(2).rotated)
	assert_eq(bag.count(&"plank"), 10)
	assert_code(bag.split(0, 1), IKResult.Code.CONTAINER_FULL)


func test_split_to_a_taken_cell_is_refused() -> void:
	var bag := _grid(3, 2)
	assert_ok(bag.add(&"plank", 10))
	assert_ok(bag.split(0, 4, 3))
	var result := bag.split(0, 2, 4)
	assert_code(result, IKResult.Code.SLOT_OCCUPIED)
	assert_code(bag.split(0, 2, 2), IKResult.Code.SLOT_OCCUPIED, "would stick out")
	assert_eq(bag.count(&"plank"), 10)


func test_remove_and_set_data_from_covered_cells() -> void:
	var bag := _grid(4, 3)
	assert_ok(bag.add(&"sword"))
	assert_ok(bag.set_data(8, {"durability": 5}))
	assert_eq(bag.get_stack(0).data, {"durability": 5})
	assert_ok(bag.remove_at(4))
	assert_eq(bag.count(&"sword"), 0)
	assert_eq(grid_map(bag), "..../..../....")
	assert_code(bag.remove_at(4), IKResult.Code.SLOT_EMPTY)


# --- Commit checks, audit, configuration ---------------------------------------------

func test_rearrange_cannot_overlap_or_stick_out() -> void:
	var bag := _grid(3, 2)
	assert_ok(bag.add(&"plank", 20))
	var before := bag.to_debug_array()
	var a := bag.get_stack(0)
	var b := bag.get_stack(3)
	var overlap := [a, b, null, null, null, null]
	var result := IKTransaction.new().rearrange(bag, overlap).commit()
	assert_code(result, IKResult.Code.INVARIANT_VIOLATION)
	assert_true(result.message.contains("overlaps"), result.message)
	var outside := [a, null, b, null, null, null]
	assert_code(IKTransaction.new().rearrange(bag, outside).commit(), IKResult.Code.INVARIANT_VIOLATION)
	assert_eq(bag.to_debug_array(), before)
	var fine := [null, null, null, a, null, null]
	fine[0] = b
	assert_ok(IKTransaction.new().rearrange(bag, fine).commit())


func test_audit_reports_broken_grids() -> void:
	var bag := _grid(2, 2)
	assert_ok(bag.add(&"plank", 3))
	var broken := bag._slots.duplicate()
	broken[1] = IKItemStack.new(&"plank", 2)
	bag._apply_slots(broken)
	var issues := IKAudit.validate([bag])
	assert_eq(issues.size(), 1, str(issues))
	assert_true(issues[0].contains("does not fit inside the grid"), str(issues))


func test_resize_grid_by_rows() -> void:
	var bag := _grid(3, 3)
	assert_ok(bag.add(&"sword"))
	assert_code(bag.resize(10), IKResult.Code.INVALID_ARGUMENT, "not whole rows")
	assert_code(bag.resize(6), IKResult.Code.SLOT_OCCUPIED, "the sword covers the last row")
	assert_ok(bag.resize(12))
	assert_eq(bag.get_grid_height(), 4)
	assert_ok(bag.move(0, 1))
	assert_ok(bag.resize(9))
	assert_eq(grid_map(bag), ".S./.S./.S.")


func test_set_grid_width_checks_the_content() -> void:
	var db := make_grid_db()
	var bag := IKContainer.new(&"bag", 6, db)
	assert_code(bag.set_grid_width(4), IKResult.Code.INVALID_ARGUMENT, "6 is not a multiple of 4")
	assert_code(bag.set_grid_width(-1), IKResult.Code.INVALID_ARGUMENT)
	assert_ok(bag.add(&"sword", 2))
	assert_code(bag.set_grid_width(3), IKResult.Code.SLOT_OCCUPIED, "swords 1x3 do not fit 2 rows")
	assert_false(bag.is_grid(), "left unchanged")
	var flat := IKContainer.new(&"flat", 6, db)
	assert_ok(flat.add(&"gem", 2))
	assert_ok(flat.set_grid_width(3))
	assert_eq(grid_map(flat), "gg./...")
	assert_ok(flat.set_grid_width(0), "back to classic slots")
	assert_false(flat.is_grid())
	assert_eq(flat.count(&"gem"), 2)


func test_inventory_node_grid_mode() -> void:
	var node := IKInventory.new()
	node.container_id = &"grid_bag"
	node.size = 10
	node.grid_width = 4
	node.database = make_grid_db()
	node.initial_items.assign({&"sword": 1, &"helmet": 1})
	add_to_tree(node)
	assert_true(node.container.is_grid())
	assert_eq(node.container.size(), 12, "rounded up to whole rows")
	assert_eq(grid_map(node.container), "SHH./SHH./S...")


func test_classic_node_is_unchanged() -> void:
	var node := IKInventory.new()
	node.size = 5
	node.database = make_grid_db()
	assert_false(node.container.is_grid())
	assert_eq(node.container.size(), 5)
	node.free()


func test_multi_container_transaction_is_atomic_with_grids() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 2, 2, db)
	var chest := IKContainer.new(&"chest", 2, db)
	assert_ok(chest.add(&"wood", 5))
	var before_bag := bag.to_debug_array()
	var before_chest := chest.to_debug_array()
	var result := IKTransaction.new() \
		.remove(chest, &"wood", 5) \
		.add(bag, &"armor") \
		.commit()
	assert_code(result, IKResult.Code.CONTAINER_FULL, "armor 2x3 does not fit a 2x2 grid")
	assert_eq(bag.to_debug_array(), before_bag)
	assert_eq(chest.to_debug_array(), before_chest)


# --- Random operations keep every guarantee ----------------------------------------

func test_random_grid_operations_keep_invariants() -> void:
	var db := make_grid_db()
	var bag := IKContainer.create_grid(&"bag", 6, 5, db)
	var chest := IKContainer.new(&"chest", 6, db)
	var cursor := IKCursor.new(db)
	var containers := [bag, chest, cursor.container]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ids := [&"wood", &"potion", &"gem", &"sword", &"helmet", &"plank", &"armor", &"staff", &"crate"]
	var expected := {}
	for step in 600:
		var op := rng.randi_range(0, 7)
		var slot := rng.randi_range(0, bag.size() - 1)
		var other := rng.randi_range(0, bag.size() - 1)
		match op:
			0:
				var item_id: StringName = ids[rng.randi_range(0, ids.size() - 1)]
				var amount := rng.randi_range(1, 6)
				var result := bag.add(item_id, amount, true)
				if result.ok:
					expected[item_id] = expected.get(item_id, 0) + amount - result.remainder
			1:
				bag.move(slot, other)
			2:
				bag.rotate(slot)
			3:
				bag.transfer_to(slot, chest)
			4:
				chest.transfer_to(rng.randi_range(0, chest.size() - 1), bag)
			5:
				cursor.primary(bag, slot)
			6:
				cursor.rotate_held()
				cursor.secondary(bag, other)
			7:
				var stack := bag.get_stack(bag.get_anchor(slot))
				if stack != null and bag.remove_at(slot, 1).ok:
					expected[stack.item_id] = expected[stack.item_id] - 1
		var issues := IKAudit.validate(containers)
		if not issues.is_empty():
			fail("step %d (op %d): %s" % [step, op, issues])
			return
	var totals := IKAudit.totals(containers)
	for item_id in expected.keys():
		if expected[item_id] == 0:
			expected.erase(item_id)
	assert_eq(totals, expected, "items are never created or lost")
