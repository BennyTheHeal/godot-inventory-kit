class_name IKItemUser
extends RefCounted
## Uses items: checks every effect, consumes the item, then applies the effects.
##
## Nothing is consumed if an effect refuses or if the slot changed. Effects run
## only after the item has been successfully consumed, so an item can never be
## used twice or used without being paid for.

const Code := IKResult.Code


## True if the item in [param slot] is usable and every effect accepts.
static func can_use(container: IKContainer, slot: int, user: Object = null) -> bool:
	return _prepare(container, slot, user).ok


static func use(container: IKContainer, slot: int, user: Object = null) -> IKResult:
	var prepared := _prepare(container, slot, user)
	if not prepared.ok:
		return prepared.result
	var context: IKUseContext = prepared.context
	if context.definition.consume_on_use:
		var consumed := container.remove_at(slot, 1)
		if not consumed.ok:
			return consumed
	for effect in context.definition.effects:
		if effect != null:
			effect.apply(context)
	return IKResult.success()


static func _prepare(container: IKContainer, slot: int, user: Object) -> Dictionary:
	var stack := container.get_stack(slot) if container != null else null
	if stack == null:
		return _refuse(IKResult.failure(Code.SLOT_EMPTY, "Nothing to use."))
	var definition := container.get_definition(slot) as IKUsableItem
	if definition == null:
		return _refuse(IKResult.failure(Code.NOT_USABLE, "This item cannot be used."))
	var context := IKUseContext.new()
	context.user = user
	context.container = container
	context.slot = slot
	context.stack = stack
	context.definition = definition
	for effect in definition.effects:
		if effect != null and not effect.can_apply(context):
			var message := context.message if not context.message.is_empty() else "This item cannot be used right now."
			var refused := IKResult.failure(Code.NOT_USABLE, message)
			refused.player_text = message  # effect messages are written for players
			return _refuse(refused)
	return {"ok": true, "context": context, "result": IKResult.success()}


static func _refuse(result: IKResult) -> Dictionary:
	return {"ok": false, "context": null, "result": result}
