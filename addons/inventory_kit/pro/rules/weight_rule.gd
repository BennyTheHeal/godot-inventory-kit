class_name IKWeightRule
extends IKContainerRule
## Limits the total weight of a container ([member IKItemDefinition.weight] x amount).
##
## A change is refused only if it makes the container heavier than the limit.
## If a container is already over the limit (rule added later, save from an older
## version...), the player can still remove or move items out of it.
## [codeblock]
## bag.rules.append(IKWeightRule.new(60.0))
## [/codeblock]

@export var max_weight := 100.0


func _init(p_max_weight: float = 100.0) -> void:
	max_weight = p_max_weight
	refusal_text = "Too heavy."


func validate_change(before: Array, after: Array, database: IKItemDatabase) -> bool:
	var weight_after := weigh(after, database)
	if weight_after <= max_weight + 0.0001:
		return true
	return weight_after <= weigh(before, database) + 0.0001


func validate_slots(slots: Array, database: IKItemDatabase) -> bool:
	return weigh(slots, database) <= max_weight + 0.0001


## Total weight of a slot array (stacks or null).
static func weigh(slots: Array, database: IKItemDatabase) -> float:
	var total := 0.0
	if database == null:
		return total
	for stack in slots:
		if stack == null:
			continue
		var definition := database.get_item(stack.item_id)
		if definition != null:
			total += definition.weight * stack.amount
	return total


## Current total weight of [param container].
static func weight_of(container: IKContainer) -> float:
	return weigh(container._slots, container.database)


## How many more [param item_id] fit under the limit of [param container]'s
## first IKWeightRule (-1 if it has none or the item weighs nothing).
static func remaining_capacity(container: IKContainer, item_id: StringName) -> int:
	var definition := container.database.get_item(item_id) if container.database else null
	if definition == null or definition.weight <= 0.0:
		return -1
	for rule in container.rules:
		if rule is IKWeightRule:
			var room: float = rule.max_weight - weight_of(container)
			return maxi(0, floori((room + 0.0001) / definition.weight))
	return -1
