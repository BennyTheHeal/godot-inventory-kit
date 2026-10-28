class_name IKItemDefinition
extends Resource
## Static description of an item type, shared by every stack of that item.
##
## Definitions are read-only at runtime. Per-copy state (durability, enchantments...)
## belongs in [member IKItemStack.data], never here.

## Stable identifier used in save files. Choose it once and never change it
## (moving or renaming the .tres file is safe, changing the id is not).
@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Maximum amount per slot. Ignored (forced to 1) when [member unique] is true.
@export_range(1, 9999, 1) var max_stack: int = 1
@export var category: StringName
@export var tags: Array[StringName] = []
## Equipment slot type this item fits in (e.g. &"weapon"). Empty = not equippable.
@export var equip_slot: StringName
@export var weight: float = 0.0
## Unique items get a uid per copy, never stack and can carry their own data.
@export var unique: bool = false
## Free-form game data (damage, price...). Shared by all copies.
@export var properties: Dictionary = {}
## Cells taken in a grid container (width x height), e.g. Vector2i(1, 3) for a
## sword. Containers with classic slots ignore it (one stack per slot).
@export var grid_size: Vector2i = Vector2i.ONE
## Grid containers may turn the item a quarter turn (width and height swap).
@export var can_rotate: bool = true


func get_effective_max_stack() -> int:
	if unique:
		return 1
	return maxi(1, max_stack)


## Cells taken in a grid, at least 1 x 1. [param rotated] swaps width and height
## (only if [member can_rotate]).
func get_grid_size(rotated: bool = false) -> Vector2i:
	var cells := Vector2i(maxi(1, grid_size.x), maxi(1, grid_size.y))
	if rotated and can_rotate:
		return Vector2i(cells.y, cells.x)
	return cells


## True if turning the item changes its shape (rotation allowed and not square).
func is_rotatable() -> bool:
	var cells := get_grid_size()
	return can_rotate and cells.x != cells.y


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
