class_name IKUseContext
extends RefCounted
## Everything an [IKItemEffect] needs to know about one use of an item.

## Who uses the item (usually the player node). May be null.
var user: Object
var container: IKContainer
var slot := -1
## Copy of the stack as it was before the use.
var stack: IKItemStack
var definition: IKUsableItem
## Set by an effect to explain a refusal.
var message := ""
