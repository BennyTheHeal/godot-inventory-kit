extends "res://tests/inventory_kit/ik_test_case.gd"
## Randomized operations (fixed seeds, reproducible). After every step:
## - item totals match an independent ledger (nothing lost, nothing duplicated),
## - IKAudit finds no invalid stack, rule violation or duplicate uid,
## - a failed operation left every container exactly as it was.

const STEPS_PER_SEED := 4000
const SEEDS := [1, 42, 20261023]
const ITEMS := [&"wood", &"stone", &"potion", &"gem", &"sword", &"helmet"]

var _rng := RandomNumberGenerator.new()
var _containers: Array[IKContainer] = []
var _ledger := {}
var _successes := {}  # operation kind -> successful runs
var _failure_count := 0


func test_random_operations_conserve_items() -> void:
	for fuzz_seed in SEEDS:
		if not _run(fuzz_seed):
			return
	# Coverage guard: every kind of operation must actually succeed regularly.
	for kind in ["add", "add_stack", "remove", "remove_at", "consume", "move", "split", "transfer", "batch"]:
		assert_true(_successes.get(kind, 0) >= 50, "'%s' succeeded only %d times" % [kind, _successes.get(kind, 0)])
	assert_true(_failure_count >= 1000, "fuzz should also exercise failures (%d)" % _failure_count)


func _run(fuzz_seed: int) -> bool:
	_rng.seed = fuzz_seed
	var db := make_db()
	_containers = [IKContainer.new(&"bag", 10, db), IKContainer.new(&"chest", 6, db), make_equipment(db),
		IKContainer.new(&"cursor", 1, db)]
	_ledger = {}
	for step in STEPS_PER_SEED:
		var before := _snapshot()
		var outcome := _random_step()
		var result: IKResult = outcome[0]
		var description: String = outcome[1]
		if result.ok:
			var kind := description.get_slice(" ", 0)
			_successes[kind] = _successes.get(kind, 0) + 1
			for item_id in outcome[2]:
				_ledger[item_id] = _ledger.get(item_id, 0) + outcome[2][item_id]
		else:
			_failure_count += 1
			if _snapshot() != before:
				fail("seed %d step %d: failed '%s' (%s) modified state" % [fuzz_seed, step, description, result])
				return false
		var issues := IKAudit.validate(_containers)
		if not issues.is_empty():
			fail("seed %d step %d after '%s': %s" % [fuzz_seed, step, description, issues])
			return false
		var totals := IKAudit.totals(_containers)
		var expected := {}
		for item_id in _ledger:
			if _ledger[item_id] != 0:
				expected[item_id] = _ledger[item_id]
		if totals != expected:
			fail("seed %d step %d after '%s': totals %s, ledger %s" % [fuzz_seed, step, description, totals, expected])
			return false
		if step % 250 == 0 and not _check_save_round_trip(fuzz_seed, step, db):
			return false
	return true


## Saved through JSON and loaded into fresh containers, the state must be identical.
func _check_save_round_trip(fuzz_seed: int, step: int, db: IKItemDatabase) -> bool:
	var doc: Dictionary = JSON.parse_string(JSON.stringify(IKSerializer.to_dict(_containers)))
	var fresh: Array[IKContainer] = [IKContainer.new(&"bag", 10, db), IKContainer.new(&"chest", 6, db),
		make_equipment(db), IKContainer.new(&"cursor", 1, db)]
	var report := IKSerializer.load_into(doc, fresh)
	var original := _snapshot()
	_containers = fresh
	if not report.ok or not report.warnings.is_empty() or _snapshot() != original:
		fail("seed %d step %d: save round trip differs (%s %s)" % [fuzz_seed, step, report, report.warnings])
		return false
	return true


## Returns [result, description, ledger delta].
func _random_step() -> Array:
	# Weights keep containers around half full, so every operation kind can succeed.
	match _rng.randi_range(0, 11):
		0, 1:
			var c := _pick_container()
			var item_id: StringName = _pick_item()
			var amount := _rng.randi_range(1, 30)
			var partial := _rng.randf() < 0.5
			var result := c.add(item_id, amount, partial)
			return [result, "add %s %d partial=%s" % [item_id, amount, partial], {item_id: amount - result.remainder}]
		2:
			var c := _pick_container()
			var stack := IKItemStack.new(&"sword", 1, "", {"durability": _rng.randi_range(1, 100)})
			return [c.add_stack(stack), "add_stack sword", {&"sword": 1}]
		3, 10:
			var c := _pick_container()
			var stack := c.get_stack(_pick_slot(c))
			var item_id: StringName = stack.item_id if stack != null else _pick_item()
			var amount := _rng.randi_range(1, 25)
			return [c.remove(item_id, amount), "remove %s %d" % [item_id, amount], {item_id: -amount}]
		4:
			var c := _pick_container()
			var slot := _rng.randi_range(-1, c.size())
			var stack := c.get_stack(slot)
			var amount := -1 if _rng.randf() < 0.5 else _rng.randi_range(0, 6)
			var delta := {}
			if stack != null:
				delta[stack.item_id] = -(stack.amount if amount < 0 else amount)
			return [c.remove_at(slot, amount), "remove_at %d %d" % [slot, amount], delta]
		5:
			var c := _pick_container()
			var requirements := {_pick_item(): _rng.randi_range(1, 8), _pick_item(): _rng.randi_range(1, 8)}
			var delta := {}
			for item_id in requirements:
				delta[item_id] = -requirements[item_id]
			return [c.try_consume(requirements), "consume %s" % requirements, delta]
		6:
			var a := _pick_container()
			var b := _pick_container()
			var from_slot := _pick_slot(a)
			var to_slot := _rng.randi_range(0, b.size() - 1)
			var amount := -1 if _rng.randf() < 0.6 else _rng.randi_range(1, 25)
			return [a.move_to(from_slot, b, to_slot, amount), "move %s[%d]->%s[%d] %d" % [a.container_id, from_slot, b.container_id, to_slot, amount], {}]
		7, 11:
			var c := _pick_container()
			var slot := _pick_slot(c)
			var to_slot := -1 if _rng.randf() < 0.5 else _rng.randi_range(0, c.size() - 1)
			var stack := c.get_stack(slot)
			var amount := _rng.randi_range(1, 20)
			if stack != null and stack.amount > 1 and _rng.randf() < 0.7:
				amount = _rng.randi_range(1, stack.amount - 1)
			return [c.split(slot, amount, to_slot), "split %s[%d] %d ->%d" % [c.container_id, slot, amount, to_slot], {}]
		8:
			var a := _pick_container()
			var b := _pick_container()
			var slot := _pick_slot(a)
			var amount := -1 if _rng.randf() < 0.5 else _rng.randi_range(1, 25)
			return [a.transfer_to(slot, b, amount), "transfer %s[%d]->%s %d" % [a.container_id, slot, b.container_id, amount], {}]
		_:
			return _random_batch()


## Several operations in one transaction; non-partial adds so the delta is exact.
func _random_batch() -> Array:
	var tx := IKTransaction.new()
	var delta := {}
	var parts := PackedStringArray()
	for i in _rng.randi_range(2, 4):
		var c := _pick_container()
		match _rng.randi_range(0, 3):
			0:
				var item_id: StringName = _pick_item()
				var amount := _rng.randi_range(1, 10)
				tx.add(c, item_id, amount)
				delta[item_id] = delta.get(item_id, 0) + amount
				parts.append("add %s %d" % [item_id, amount])
			1:
				# Mostly remove something that exists (amounts may still exceed what's left).
				var slot := _pick_slot(c)
				var stack := c.get_stack(slot)
				var item_id: StringName = stack.item_id if stack != null else _pick_item()
				var amount := _rng.randi_range(1, 3)
				tx.remove(c, item_id, amount)
				delta[item_id] = delta.get(item_id, 0) - amount
				parts.append("remove %s %d" % [item_id, amount])
			2:
				var b := _pick_container()
				tx.move(c, _pick_slot(c), b, _rng.randi_range(0, b.size() - 1))
				parts.append("move")
			3:
				var b := _pick_container()
				tx.transfer(c, _pick_slot(c), b)
				parts.append("transfer")
	return [tx.commit(), "batch [%s]" % ", ".join(parts), delta]


func _pick_container() -> IKContainer:
	return _containers[_rng.randi_range(0, _containers.size() - 1)]


## An occupied slot 80% of the time (when there is one), otherwise any slot.
func _pick_slot(c: IKContainer) -> int:
	var occupied := []
	for i in c.size():
		if not c.is_slot_empty(i):
			occupied.append(i)
	if not occupied.is_empty() and _rng.randf() < 0.8:
		return occupied[_rng.randi_range(0, occupied.size() - 1)]
	return _rng.randi_range(0, c.size() - 1)


func _pick_item() -> StringName:
	return ITEMS[_rng.randi_range(0, ITEMS.size() - 1)]


func _snapshot() -> Array:
	var result := []
	for c in _containers:
		result.append(c.to_debug_array())
	return result
