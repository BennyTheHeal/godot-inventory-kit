extends "res://tests/inventory_kit/ik_test_case.gd"
## The free Lite edition is the addon without its pro/ folder: Lite files must
## never depend on anything inside pro/.

const ADDON := "res://addons/inventory_kit/"
const PRO := ADDON + "pro/"


func test_pro_classes_exist() -> void:
	if not DirAccess.dir_exists_absolute(PRO):
		return  # Lite edition: no pro/ folder at all, which is the point
	assert_true(_pro_classes().has("IKInputController"), "the check below must have something to look for")


func test_lite_files_do_not_reference_pro_modules() -> void:
	if OS.has_feature("template"):
		return  # source files are not in exported games
	var pro_classes := _pro_classes()
	var lite_files := _scripts(ADDON)
	lite_files.append_array(_scripts("res://demo/lite/"))
	for path in lite_files:
		if path.begins_with(PRO):
			continue
		var source := FileAccess.get_file_as_string(path)
		if source.contains("addons/inventory_kit/pro"):
			fail("%s references a pro/ path" % path)
		for class_id in pro_classes:
			var regex := RegEx.create_from_string("\\b%s\\b" % class_id)
			if regex.search(source) != null:
				fail("%s uses pro class %s" % [path, class_id])


func test_every_addon_script_declares_a_prefixed_class() -> void:
	if OS.has_feature("template"):
		return  # source files are not in exported games
	for path in _scripts(ADDON):
		if path.ends_with("plugin.gd") or path.begins_with(PRO + "editor/"):
			continue  # editor-only scripts
		var source := FileAccess.get_file_as_string(path)
		var regex := RegEx.create_from_string("(?m)^class_name (\\w+)")
		var found := regex.search(source)
		if found == null:
			fail("%s has no class_name" % path)
		elif not found.get_string(1).begins_with("IK"):
			fail("%s: class %s lacks the IK prefix" % [path, found.get_string(1)])


func _pro_classes() -> PackedStringArray:
	var result := PackedStringArray()
	for info in ProjectSettings.get_global_class_list():
		if String(info.path).begins_with(PRO):
			result.append(info["class"])
	return result


func _scripts(directory: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			result.append(directory + file)
	for sub in DirAccess.get_directories_at(directory):
		result.append_array(_scripts(directory + sub + "/"))
	return result
