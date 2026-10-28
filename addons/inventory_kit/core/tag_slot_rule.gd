class_name IKTagSlotRule
extends IKSlotRule
## Accepts items by category and/or tag. Empty lists mean "no restriction".

## The item's category must be one of these.
@export var categories: Array[StringName] = []
## The item must have at least one of these tags.
@export var any_tags: Array[StringName] = []


func accepts(_stack: IKItemStack, definition: IKItemDefinition) -> bool:
	if not categories.is_empty() and not categories.has(definition.category):
		return false
	if any_tags.is_empty():
		return true
	for tag in any_tags:
		if definition.has_tag(tag):
			return true
	return false
