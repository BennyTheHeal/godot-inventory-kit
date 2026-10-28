class_name IKAudit
extends RefCounted
## Consistency checks across several containers (debug tools, tests, after loading).


## Item id -> total amount across [param containers].
static func totals(containers: Array) -> Dictionary:
	var result := {}
	for container in containers:
		IKContainer._accumulate_totals(container._slots, result)
	return result


## Every uid that appears more than once.
static func find_duplicate_uids(containers: Array) -> PackedStringArray:
	var seen := {}
	var duplicates := PackedStringArray()
	for container in containers:
		for stack in container._slots:
			if stack == null or not stack.has_uid():
				continue
			if seen.has(stack.uid) and not duplicates.has(stack.uid):
				duplicates.append(stack.uid)
			seen[stack.uid] = true
	return duplicates


## Human-readable problems: unknown items, bad amounts, rule violations, duplicate uids,
## overlapping or out-of-grid items in grid containers.
static func validate(containers: Array) -> PackedStringArray:
	var issues := PackedStringArray()
	for container: IKContainer in containers:
		var label := String(container.container_id)
		for i in container.size():
			var stack: IKItemStack = container._slots[i]
			if stack == null:
				continue
			var definition := container.database.get_item(stack.item_id) if container.database else null
			if definition == null:
				issues.append("%s[%d]: unknown item '%s'." % [label, i, stack.item_id])
				continue
			if stack.amount < 1 or stack.amount > definition.get_effective_max_stack():
				issues.append("%s[%d]: amount %d out of range for '%s'." % [label, i, stack.amount, stack.item_id])
			if definition.unique and not stack.has_uid():
				issues.append("%s[%d]: unique item '%s' has no uid." % [label, i, stack.item_id])
			if not container._accepts(i, stack, definition):
				issues.append("%s[%d]: '%s' violates a rule." % [label, i, stack.item_id])
		for problem in container._grid_issues(container._slots):
			issues.append("%s: %s" % [label, problem])
	for uid in find_duplicate_uids(containers):
		issues.append("Duplicate uid %s." % uid)
	return issues
