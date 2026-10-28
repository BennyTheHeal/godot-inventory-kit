@tool
extends EditorInspectorPlugin
## Shows problems at the top of the inspector for item databases and definitions:
## duplicate or empty ids, unique items with a stack size, missing icons.


func _can_handle(object: Object) -> bool:
	return object is IKItemDatabase or object is IKItemDefinition


func _parse_begin(object: Object) -> void:
	var issues := PackedStringArray()
	if object is IKItemDatabase:
		issues = (object as IKItemDatabase).validate()
		for definition in (object as IKItemDatabase).items:
			if definition != null and definition.id != &"" and definition.icon == null:
				issues.append("Item '%s' has no icon." % definition.id)
		var summary := "%d items" % (object as IKItemDatabase).items.size()
		add_custom_control(_label(summary + (" — no problems found" if issues.is_empty() else ""), issues.is_empty()))
	else:
		var definition := object as IKItemDefinition
		if definition.id == &"":
			issues.append("Set an id: save files store items by id.")
		if definition.unique and definition.max_stack > 1:
			issues.append("Unique items never stack: max_stack is ignored.")
		if definition.icon == null:
			issues.append("No icon: the slot will look empty.")
	for issue in issues:
		add_custom_control(_label("⚠ " + issue, false))


func _label(text: String, ok: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", Color(0.55, 0.85, 0.55) if ok else Color(1.0, 0.75, 0.35))
	return label
