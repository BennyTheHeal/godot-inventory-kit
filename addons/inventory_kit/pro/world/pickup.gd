class_name IKPickup
extends RefCounted
## Shared logic of [IKWorldItem2D] and [IKWorldItem3D]: moving a world stack into
## an inventory, and finding the inventory of whatever touched the item.


## Adds as much of [param stack] as fits into [param container]. On success,
## [member IKResult.remainder] is what stayed on the ground (0 = all collected).
static func collect(stack: IKItemStack, container: IKContainer) -> IKResult:
	if stack == null or stack.amount <= 0:
		return IKResult.failure(IKResult.Code.INVALID_ARGUMENT, "Nothing to pick up.")
	if container == null:
		return IKResult.failure(IKResult.Code.INVALID_ARGUMENT, "No inventory to pick up into.")
	var result := container.add_stack(stack, true)
	if result.ok and result.remainder == stack.amount:
		return IKResult.failure(IKResult.Code.CONTAINER_FULL, "No room for %s." % stack.item_id)
	return result


## The container of a collector: [param node] itself if it is an [IKInventory],
## its [code]inventory[/code] property (IKInventory or IKContainer), or its first
## IKInventory child.
static func find_container(node: Node) -> IKContainer:
	if node == null:
		return null
	if node is IKInventory:
		return node.container
	var property: Variant = node.get(&"inventory")
	if property is IKInventory:
		return property.container
	if property is IKContainer:
		return property
	for child in node.get_children():
		if child is IKInventory:
			return child.container
	return null

