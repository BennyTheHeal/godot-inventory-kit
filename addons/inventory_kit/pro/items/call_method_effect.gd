class_name IKCallMethodEffect
extends IKItemEffect
## Calls [member method] on the user with [member arguments], e.g. heal(50).
## If [member check_method] is set, it is called first with the same arguments
## and must return true for the item to be used (e.g. can_heal(50)).

@export var method: StringName
@export var arguments: Array = []
@export var check_method: StringName


func can_apply(context: IKUseContext) -> bool:
	var user := context.user
	if user == null or not user.has_method(method):
		context.message = "Nothing can use this item."
		return false
	if check_method != &"":
		if not user.has_method(check_method) or not user.callv(check_method, arguments):
			context.message = "This item cannot be used right now."
			return false
	return true


func apply(context: IKUseContext) -> void:
	context.user.callv(method, arguments)
