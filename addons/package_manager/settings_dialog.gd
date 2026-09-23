@tool
extends AcceptDialog

signal settings_saved

@onready var _store_path_edit: LineEdit = $VBox/StorePathSection/PathRow/StorePathEdit
@onready var _browse_btn: Button = $VBox/StorePathSection/PathRow/BrowseBtn
@onready var _open_folder_btn: Button = $VBox/StorePathSection/PathRow/OpenFolderBtn
@onready var _overwrite_check: CheckBox = $VBox/OverwriteCheck
@onready var _warning_label: Label = $VBox/WarningLabel


func _ready() -> void:
	get_ok_button().pressed.connect(_on_save_pressed)
	_browse_btn.pressed.connect(_on_browse_pressed)
	_open_folder_btn.pressed.connect(_on_open_folder_pressed)
	_load_current()


func _get_settings_cfg_path() -> String:
	return PackageManagerUtil.get_settings_file_path()


func _load_current() -> void:
	_store_path_edit.text = PackageManagerUtil.get_store_path()
	var cfg := ConfigFile.new()
	var path := _get_settings_cfg_path()
	if FileAccess.file_exists(path) and cfg.load(path) == OK:
		_overwrite_check.button_pressed = cfg.get_value("package_manager", "overwrite_existing", false)
	else:
		_overwrite_check.button_pressed = false
	_update_warning()


func _update_warning() -> void:
	var p := _store_path_edit.text.strip_edges()
	if p.is_empty():
		_warning_label.text = "Store path is empty. Default will be used."
		_warning_label.visible = true
		return
	var abs_path := p
	if p.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(p)
	elif p.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(p)
	if not DirAccess.dir_exists_absolute(abs_path):
		var d := DirAccess.open(abs_path.get_base_dir())
		if d == null:
			_warning_label.text = "Parent folder does not exist or path is invalid."
			_warning_label.visible = true
			return
		_warning_label.text = "Folder will be created on first pack."
		_warning_label.visible = true
	else:
		_warning_label.visible = false


func _on_browse_pressed() -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	fd.access = EditorFileDialog.ACCESS_FILESYSTEM
	fd.title = "Select package store folder"
	fd.dir_selected.connect(_on_dir_selected)
	add_child(fd)
	var current := _store_path_edit.text.strip_edges()
	if current.is_empty():
		fd.current_dir = PackageManagerUtil.get_default_store_path()
	else:
		fd.current_dir = PackageManagerUtil.globalize(current) if current.begins_with("user://") or current.begins_with("res://") else current
	fd.popup_centered_ratio(0.5)


func _on_dir_selected(dir: String) -> void:
	_store_path_edit.text = dir
	_update_warning()


func _on_open_folder_pressed() -> void:
	var p := _store_path_edit.text.strip_edges()
	if p.is_empty():
		p = PackageManagerUtil.get_default_store_path()
	else:
		p = PackageManagerUtil.globalize(p) if p.begins_with("user://") or p.begins_with("res://") else p
	if not DirAccess.dir_exists_absolute(p):
		p = p.get_base_dir()
	OS.shell_open(p)


func _on_save_pressed() -> void:
	var path_text := _store_path_edit.text.strip_edges()
	if path_text.is_empty():
		path_text = PackageManagerUtil.get_default_store_path()
	var err := PackageManagerUtil.set_store_path(path_text)
	if err != OK:
		return
	var cfg := ConfigFile.new()
	var cfg_path := _get_settings_cfg_path()
	if FileAccess.file_exists(cfg_path):
		cfg.load(cfg_path)
	cfg.set_value("package_manager", "store_path", path_text)
	cfg.set_value("package_manager", "overwrite_existing", _overwrite_check.button_pressed)
	cfg.save(cfg_path)
	settings_saved.emit()
	hide()
