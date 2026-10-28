extends SceneTree
## Headless test runner. No dependencies.
##
##   godot --headless --path <project> -s res://tests/inventory_kit/run_tests.gd
##   godot --headless --path <project> -s res://tests/inventory_kit/run_tests.gd -- fuzz
##
## Runs every test_*() method of every test_*.gd file in this folder (optionally
## only files whose name contains the filter). Engine and script errors raised
## during a test fail that test. Exit code is 0 only if every test passed.

const TEST_DIR := "res://tests/inventory_kit/"


class ErrorCatcher extends Logger:
	var count := 0
	var last := ""
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		last = "%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
		_mutex.unlock()


func _initialize() -> void:
	_run()


# Coroutine: tests may await frames (UI layout, input), so the main loop must keep running.
func _run() -> void:
	await process_frame  # the root is not inside the tree yet during _initialize()
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if args.size() > 0 else ""

	var passed := 0
	var failures := PackedStringArray()
	var started := Time.get_ticks_msec()
	var files := []
	for file in DirAccess.get_files_at(TEST_DIR):
		# Exported builds list compiled scripts as "x.gd.remap" / "x.gdc".
		var source := file.trim_suffix(".remap")
		if source.ends_with(".gdc"):
			source = source.trim_suffix(".gdc") + ".gd"
		if not files.has(source):
			files.append(source)
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		if not filter.is_empty() and not file.contains(filter):
			continue
		var errors_before := catcher.count
		var script: GDScript = load(TEST_DIR + file)
		if script == null or not script.can_instantiate() or catcher.count != errors_before:
			failures.append("%s: failed to load (%s)" % [file, catcher.last])
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			var test: Object = script.new()
			errors_before = catcher.count
			await test.call(test_name)
			await test.cleanup()
			var problems: PackedStringArray = test.get_failures()
			if catcher.count != errors_before:
				problems.append("engine/script error: " + catcher.last)
			if problems.is_empty():
				passed += 1
			else:
				for problem in problems:
					failures.append("%s::%s — %s" % [file.get_basename(), test_name, problem])

	OS.remove_logger(catcher)
	for failure in failures:
		print("FAIL ", failure)
	var failed_tests := {}
	for failure in failures:
		failed_tests[failure.get_slice(" — ", 0)] = true
	print("\n%d passed, %d failed (%d ms)" % [passed, failed_tests.size(), Time.get_ticks_msec() - started])
	quit(0 if failures.is_empty() else 1)
