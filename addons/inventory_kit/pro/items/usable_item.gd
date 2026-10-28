class_name IKUsableItem
extends IKItemDefinition
## An item that can be used from the inventory or the hotbar (potion, food, scroll...).
##
## Create IKUsableItem resources instead of IKItemDefinition for these items; they
## work everywhere a definition does. Using one runs its [member effects] through
## [IKItemUser].

## Remove one item from the stack when used.
@export var consume_on_use := true
## Applied in order when the item is used. All of them must accept the use.
@export var effects: Array[IKItemEffect] = []
