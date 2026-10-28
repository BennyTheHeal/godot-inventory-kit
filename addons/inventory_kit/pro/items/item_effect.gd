class_name IKItemEffect
extends Resource
## What happens when an [IKUsableItem] is used. Extend it for your own effects,
## or use [IKCallMethodEffect] to call a method on the user without code.
## [codeblock]
## class_name HealEffect extends IKItemEffect
## @export var amount := 25
## func can_apply(context: IKUseContext) -> bool:
##     return context.user.health < context.user.max_health   # no potion wasted at full health
## func apply(context: IKUseContext) -> void:
##     context.user.heal(amount)
## [/codeblock]


## Return false to refuse the use (nothing is consumed). [member IKUseContext.message]
## (English, translated through [IKText]) tells the player why.
## can explain why.
func can_apply(_context: IKUseContext) -> bool:
	return true


func apply(_context: IKUseContext) -> void:
	pass
