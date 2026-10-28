@tool
extends EditorPlugin
## Editor entry point. The core runtime needs no plugin activation:
## every class is available through its class_name.

# Optional editor tools of the Standard edition (absent from the Lite edition).
const EXTRA_INSPECTOR := "pro/editor/database_inspector.gd"

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	var path: String = get_script().resource_path.get_base_dir().path_join(EXTRA_INSPECTOR)
	if ResourceLoader.exists(path):
		_inspector = load(path).new()
		add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null
