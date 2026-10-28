extends "res://tests/inventory_kit/ik_test_case.gd"
## Atomic save file: checksum, backup rotation, recovery.

const DIR := "user://ik_tests"
const PATH := DIR + "/inventory.json"


func _clean() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _bag(db: IKItemDatabase) -> IKContainer:
	return IKContainer.new(&"bag", 4, db)


func _write_text(file_path: String, text: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _corrupt(file_path: String) -> void:
	var text := FileAccess.get_file_as_string(file_path)
	_write_text(file_path, text.substr(0, text.length() - 20))


func test_save_then_load() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	bag.add(&"wood", 7)
	assert_eq(IKSaveFile.new(PATH).save([bag]), OK)
	assert_true(FileAccess.file_exists(PATH))
	assert_false(FileAccess.file_exists(PATH + ".tmp"), "temp file renamed")
	var loaded := _bag(db)
	var report := IKSaveFile.new(PATH).load_into([loaded])
	assert_true(report.ok, str(report))
	assert_eq(report.source, "main")
	assert_eq(loaded.count(&"wood"), 7)
	_clean()


func test_second_save_keeps_previous_as_backup() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	var save := IKSaveFile.new(PATH)
	bag.add(&"wood", 1)
	save.save([bag])
	bag.add(&"wood", 1)
	save.save([bag])
	var backup := IKSaveFile.read_document(PATH + ".bak")
	assert_true(backup.ok)
	var restored := _bag(db)
	IKSerializer.load_into(backup.doc, [restored])
	assert_eq(restored.count(&"wood"), 1, "backup holds the previous save")
	_clean()


func test_damaged_main_falls_back_to_backup() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	var save := IKSaveFile.new(PATH)
	bag.add(&"wood", 3)
	save.save([bag])
	bag.add(&"wood", 2)
	save.save([bag])
	_corrupt(PATH)
	var loaded := _bag(db)
	var report := save.load_into([loaded])
	assert_true(report.ok, str(report))
	assert_eq(report.source, "backup")
	assert_eq(loaded.count(&"wood"), 3)
	assert_true(report.warnings.size() >= 1, "the damaged file is reported")
	_clean()


func test_saving_after_recovery_keeps_the_good_backup() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	var save := IKSaveFile.new(PATH)
	bag.add(&"wood", 3)
	save.save([bag])
	save.save([bag])
	_corrupt(PATH)
	bag.add(&"stone", 1)
	assert_eq(save.save([bag]), OK)
	assert_true(FileAccess.file_exists(PATH + ".corrupt"), "damaged main set aside")
	assert_true(IKSaveFile.read_document(PATH + ".bak").ok, "backup is still a valid save")
	_clean()


func test_interrupted_save_recovers_from_temp() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	bag.add(&"gem", 1)
	IKSaveFile.write_document(PATH, IKSerializer.to_dict([bag]))
	# Simulate a crash after the main file was moved to .bak but before .tmp was renamed.
	DirAccess.rename_absolute(PATH, PATH + ".tmp")
	var loaded := _bag(db)
	var report := IKSaveFile.new(PATH).load_into([loaded])
	assert_true(report.ok, str(report))
	assert_eq(report.source, "tmp")
	assert_eq(loaded.count(&"gem"), 1)
	_clean()


func test_garbage_temp_file_is_ignored() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	bag.add(&"wood", 4)
	IKSaveFile.new(PATH).save([bag])
	_write_text(PATH + ".tmp", "half-written gar")
	var loaded := _bag(db)
	var report := IKSaveFile.new(PATH).load_into([loaded])
	assert_eq(report.source, "main")
	assert_eq(loaded.count(&"wood"), 4)
	_clean()


func test_edited_payload_fails_checksum() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	bag.add(&"wood", 4)
	IKSaveFile.new(PATH).save([bag])
	var text := FileAccess.get_file_as_string(PATH)
	_write_text(PATH, text.replace("\"n\": 4", "\"n\": 9"))
	var read := IKSaveFile.read_document(PATH)
	assert_false(read.ok)
	assert_true(read.error.contains("checksum"), read.error)
	_clean()


func test_newer_save_is_refused_without_falling_back() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	bag.add(&"wood", 1)
	var save := IKSaveFile.new(PATH)
	save.save([bag])
	var newer := IKSerializer.to_dict([bag])
	newer.version = 99
	IKSaveFile.write_document(PATH, newer)
	var loaded := _bag(db)
	var report := save.load_into([loaded])
	assert_false(report.ok, "must not silently load the older backup")
	assert_true(report.error.contains("newer"), report.error)
	assert_eq(loaded.count(&"wood"), 0)
	_clean()


func test_missing_and_fully_damaged_saves() -> void:
	_clean()
	var bag := _bag(make_db())
	var save := IKSaveFile.new(PATH)
	assert_false(save.exists())
	var report := save.load_into([bag])
	assert_false(report.ok)
	assert_true(report.error.begins_with("No save file"), report.error)
	_write_text(PATH, "nonsense")
	report = save.load_into([bag])
	assert_false(report.ok)
	assert_true(report.error.contains("damaged"), report.error)
	_clean()


func test_unmatched_containers_survive_a_save() -> void:
	_clean()
	var db := make_db()
	var bag := _bag(db)
	var bank := IKContainer.new(&"bank", 2, db)
	bank.add(&"gem", 1)
	IKSaveFile.new(PATH).save([bag, bank])
	var save := IKSaveFile.new(PATH)
	assert_true(save.load_into([bag]).ok, "load the bag only")
	bag.add(&"wood", 2)
	save.save([bag])
	var bank2 := IKContainer.new(&"bank", 2, db)
	assert_true(IKSaveFile.new(PATH).load_into([bag, bank2]).ok)
	assert_eq(bank2.count(&"gem"), 1, "bank data kept although it was not loaded")
	_clean()


func test_creates_missing_directories() -> void:
	var nested := DIR + "/deep/slot1/inventory.json"
	var bag := _bag(make_db())
	assert_eq(IKSaveFile.new(nested).save([bag]), OK)
	assert_true(FileAccess.file_exists(nested))
	DirAccess.remove_absolute(nested)
	DirAccess.remove_absolute(DIR + "/deep/slot1")
	DirAccess.remove_absolute(DIR + "/deep")
