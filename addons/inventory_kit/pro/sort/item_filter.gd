class_name IKItemFilter
extends RefCounted
## Ready-made filters for [member IKContainerView.filter]. Each returns a
## Callable(stack: IKItemStack, definition: IKItemDefinition) -> bool.
## [codeblock]
## bag_view.filter = IKItemFilter.category(&"consumable")
## bag_view.filter = IKItemFilter.text(search_box.text)
## bag_view.filter = Callable()   # show everything
## [/codeblock]


static func category(value: StringName) -> Callable:
	return func(_stack: IKItemStack, definition: IKItemDefinition) -> bool:
		return definition != null and definition.category == value


static func tag(value: StringName) -> Callable:
	return func(_stack: IKItemStack, definition: IKItemDefinition) -> bool:
		return definition != null and definition.has_tag(value)


## Items that fit an equipment slot type (any slot if [param equip_slot] is empty).
static func equippable(equip_slot: StringName = &"") -> Callable:
	return func(_stack: IKItemStack, definition: IKItemDefinition) -> bool:
		return definition != null and definition.equip_slot != &"" \
			and (equip_slot == &"" or definition.equip_slot == equip_slot)


## Case-insensitive search in name, id, category and tags. Empty query = everything.
static func text(query: String) -> Callable:
	var needle := query.strip_edges().to_lower()
	return func(stack: IKItemStack, definition: IKItemDefinition) -> bool:
		if needle.is_empty():
			return true
		if String(stack.item_id).to_lower().contains(needle):
			return true
		if definition == null:
			return false
		if definition.display_name.to_lower().contains(needle) or String(definition.category).to_lower().contains(needle):
			return true
		for item_tag in definition.tags:
			if String(item_tag).to_lower().contains(needle):
				return true
		return false


## Matches when every given filter matches.
static func all(filters: Array[Callable]) -> Callable:
	return func(stack: IKItemStack, definition: IKItemDefinition) -> bool:
		for item_filter in filters:
			if not item_filter.call(stack, definition):
				return false
		return true


## Matches when at least one given filter matches.
static func any(filters: Array[Callable]) -> Callable:
	return func(stack: IKItemStack, definition: IKItemDefinition) -> bool:
		for item_filter in filters:
			if item_filter.call(stack, definition):
				return true
		return false
