extends "res://tests/inventory_kit/ik_test_case.gd"
## Player texts: translation through Godot's TranslationServer, and the shipped templates.

const TRANSLATIONS := "res://addons/inventory_kit/translations/"


func _with_french(messages: Dictionary) -> Translation:
	var translation := Translation.new()
	translation.locale = "fr"
	for key in messages:
		translation.add_message(key, messages[key])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("fr")
	return translation


func _restore(translation: Translation, locale: String) -> void:
	TranslationServer.remove_translation(translation)
	TranslationServer.set_locale(locale)


func test_slot_tooltip_and_refusals_follow_the_locale() -> void:
	var locale := TranslationServer.get_locale()
	var db := make_db()
	db.get_item(&"wood").description = "Burns well."
	var bag := IKContainer.new(&"bag", 2, db)
	bag.add(&"wood", 3)
	var view := IKContainerView.new()
	add_to_tree(view)
	view.bind(bag)
	assert_eq(view.get_slot_view(0).tooltip_text, "Wood\nBurns well.")
	var french := _with_french({"Wood": "Bois", "Burns well.": "Brûle bien.", "Not enough room.": "Pas assez de place."})
	assert_eq(view.get_slot_view(0).tooltip_text, "Bois\nBrûle bien.", "slots refresh when the locale changes")
	var full := IKResult.failure(IKResult.Code.CONTAINER_FULL, "No room for 'wood'.")
	assert_eq(IKText.result_message(full), "Pas assez de place.")
	assert_eq(full.message, "No room for 'wood'.", "the technical message is untouched")
	_restore(french, locale)
	assert_eq(IKText.result_message(full), "Not enough room.")


func test_result_texts_can_be_reworded() -> void:
	var refused := IKResult.failure(IKResult.Code.SLOT_FULL, "Slot 3 is full.")
	var original: String = IKText.result_texts[IKResult.Code.SLOT_FULL]
	IKText.result_texts[IKResult.Code.SLOT_FULL] = "No more space in that slot!"
	assert_eq(IKText.result_message(refused), "No more space in that slot!")
	IKText.result_texts[IKResult.Code.SLOT_FULL] = original
	refused.player_text = "Too heavy."
	assert_eq(IKText.result_message(refused), "Too heavy.", "a rule's own text wins")
	assert_eq(IKText.result_message(IKResult.success()), "")


func test_container_rule_refusal_text() -> void:
	var db := make_db()
	var chest := IKContainer.new(&"chest", 2, db)
	var locked := _LockedRule.new()
	locked.refusal_text = "The chest is locked."
	chest.rules.append(locked)
	var result := chest.add(&"wood")
	assert_code(result, IKResult.Code.RULE_REJECTED)
	assert_eq(IKText.result_message(result), "The chest is locked.")


class _LockedRule extends IKContainerRule:
	func validate_slots(_slots: Array, _database: IKItemDatabase) -> bool:
		return false


## Every IKText.t("...") literal of the code shipped in this edition is in a template.
func test_templates_list_every_text_of_the_code() -> void:
	if OS.has_feature("template"):
		return  # source files are not in exported games
	var keys := {}
	for file in DirAccess.get_files_at(TRANSLATIONS):
		if file.ends_with(".csv"):
			var csv := FileAccess.open(TRANSLATIONS + file, FileAccess.READ)
			while not csv.eof_reached():
				var row := csv.get_csv_line()
				if row.size() >= 2:
					keys[row[0]] = true
	assert_true(keys.has("keys"), "templates found")
	var pattern := RegEx.create_from_string("IKText\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var missing := PackedStringArray()
	for path in _scripts("res://addons/inventory_kit/"):
		for match in pattern.search_all(FileAccess.get_file_as_string(path)):
			var text := match.get_string(1).c_unescape()
			if not keys.has(text):
				missing.append(text)
	for text in IKText.result_texts.values():
		if not keys.has(text):
			missing.append(text)
	assert_eq(missing.size(), 0, "missing from the templates (run tools/make_translation_template.py): %s" % missing)


func _scripts(folder: String, into: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			into.append(folder + file)
	for sub in DirAccess.get_directories_at(folder):
		_scripts(folder + sub + "/", into)
	return into
