@tool
extends AcceptDialog

signal create_package_requested(package_id: String, display_name: String, version: String, description: String, paths: PackedStringArray)

@onready var _id_edit: LineEdit = $VBox/Form/IdEdit
@onready var _name_edit: LineEdit = $VBox/Form/NameEdit
@onready var _version_edit: LineEdit = $VBox/Form/VersionEdit
@onready var _description_edit: TextEdit = $VBox/Form/DescriptionEdit
@onready var _paths_list: ItemList = $VBox/PathsSection/PathsList
@onready var _add_files_btn: Button = $VBox/PathsSection/PathButtons/AddFilesBtn
@onready var _add_folder_btn: Button = $VBox/PathsSection/PathButtons/AddFolderBtn
@onready var _remove_path_btn: Button = $VBox/PathsSection/PathButtons/RemovePathBtn
@onready var _error_label: Label = $VBox/ErrorLabel
@onready var _create_btn: Button = get_ok_button()

var _file_dialog: EditorFileDialog
var _plugin: EditorPlugin


func _ready() -> void:
	title = "Create Package"
	_create_btn.text = "Create"
	_create_btn.pressed.connect(_on_create_pressed)
	_add_files_btn.pressed.connect(_on_add_files_pressed)
	_add_folder_btn.pressed.connect(_on_add_folder_pressed)
	_remove_path_btn.pressed.connect(_on_remove_path_pressed)
	_id_edit.text_changed.connect(_on_validate)
	close_requested.connect(_on_close_requested)
	_install_file_dialog()


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _install_file_dialog() -> void:
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.set_meta("_script_owner", self)
	add_child(_file_dialog)
	_file_dialog.files_selected.connect(_on_files_selected)
	_file_dialog.dir_selected.connect(_on_dir_selected)


func _on_add_files_pressed() -> void:
	if _file_dialog:
		_file_dialog.clear_filters()
		_file_dialog.add_filter("*.*", "All files")
		_file_dialog.title = "Select files to pack"
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
		_file_dialog.current_dir = ProjectSettings.globalize_path("res://")
		_file_dialog.popup_centered_ratio(0.6)


func _on_add_folder_pressed() -> void:
	if _file_dialog:
		_file_dialog.title = "Select folder to pack"
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_file_dialog.current_dir = ProjectSettings.globalize_path("res://")
		_file_dialog.popup_centered_ratio(0.6)


func _paths_list_index_of(text: String) -> int:
	for i in _paths_list.item_count:
		if _paths_list.get_item_text(i) == text:
			return i
	return -1


func _path_to_relative(path: String) -> String:
	path = path.strip_edges()
	if path.begins_with("res://"):
		var rel := path.substr(6).lstrip("/")
		return rel if not rel.is_empty() else "."
	var project_path := ProjectSettings.globalize_path("res://")
	if path.begins_with(project_path):
		var rel := path.substr(project_path.length()).lstrip("/\\").replace("\\", "/")
		return rel if not rel.is_empty() else "."
	return ""


func _on_dir_selected(dir: String) -> void:
	# In OPEN_DIR mode, dir_selected often passes current_dir (parent). Prefer current_path for the actually selected folder.
	var path_to_use := dir
	if _file_dialog and _file_dialog.file_mode == EditorFileDialog.FILE_MODE_OPEN_DIR:
		var current_path := _file_dialog.current_path.strip_edges()
		if not current_path.is_empty():
			path_to_use = current_path
		else:
			# current_path can be empty on some platforms; avoid adding the parent by requiring a real selection
			_show_error("Select a folder by clicking it, then press Open/Select.")
			return
	var rel := _path_to_relative(path_to_use)
	if rel.is_empty() or rel == ".":
		_show_error("Project root cannot be packed as a single folder.")
		return
	# Avoid adding a path that is already covered by an existing path (e.g. parent folder)
	if _paths_list_index_of(rel) >= 0:
		return
	var idx := 0
	while idx < _paths_list.item_count:
		var existing := _paths_list.get_item_text(idx)
		if rel == existing or rel.begins_with(existing + "/"):
			return  # already covered
		if existing.begins_with(rel + "/"):
			_paths_list.remove_item(idx)
			continue
		idx += 1
	_paths_list.add_item(rel)
	_show_error("")


func _on_files_selected(paths: PackedStringArray) -> void:
	for p in paths:
		var rel := _path_to_relative(p)
		if rel.is_empty():
			continue
		if _paths_list_index_of(rel) < 0:
			_paths_list.add_item(rel)


func _on_remove_path_pressed() -> void:
	var sel := _paths_list.get_selected_items()
	for i in range(sel.size() - 1, -1, -1):
		_paths_list.remove_item(sel[i])


func _on_create_pressed() -> void:
	var id_text := _id_edit.text.strip_edges()
	var err := _validate_id(id_text)
	if not err.is_empty():
		_show_error(err)
		return
	var paths: PackedStringArray = []
	for i in _paths_list.item_count:
		paths.append(_paths_list.get_item_text(i))
	if paths.is_empty():
		_show_error("Add at least one file or folder to pack.")
		return
	_show_error("")
	create_package_requested.emit(
		id_text,
		_name_edit.text.strip_edges() if _name_edit.text else id_text,
		_version_edit.text.strip_edges(),
		_description_edit.text.strip_edges(),
		paths
	)
	hide()


func _validate_id(id: String) -> String:
	if id.is_empty():
		return "Package ID is required."
	var invalid := "/\\:*?\"<>|"
	for c in id:
		if c in invalid:
			return "Package ID cannot contain: / \\ : * ? \" < > |"
	return ""


func _on_validate(_new_text: String) -> void:
	_on_validate_id_field()


func _on_validate_id_field() -> void:
	var err := _validate_id(_id_edit.text.strip_edges())
	_error_label.visible = not err.is_empty()
	_error_label.text = err


func _show_error(msg: String) -> void:
	_error_label.visible = not msg.is_empty()
	_error_label.text = msg


func _on_close_requested() -> void:
	_show_error("")


func clear_form() -> void:
	_id_edit.clear()
	_name_edit.clear()
	_version_edit.clear()
	_description_edit.clear()
	_paths_list.clear()
	_show_error("")
