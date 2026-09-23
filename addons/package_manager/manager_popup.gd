@tool
extends Window

## Reference to the plugin, set when instantiated.
var plugin: EditorPlugin

const PackDialogScene = preload("res://addons/package_manager/pack_dialog.tscn")
const PreviewPanelScene = preload("res://addons/package_manager/preview_panel.tscn")
const SettingsDialogScene = preload("res://addons/package_manager/settings_dialog.tscn")
const InstallConfigDialogScene = preload("res://addons/package_manager/install_config_dialog.tscn")

@onready var _toolbar: HBoxContainer = $MarginContainer/VBox/Toolbar
@onready var _list_container: VBoxContainer = $MarginContainer/VBox/ListContainer
@onready var _status_label: Label = $MarginContainer/VBox/StatusBar/StatusLabel
@onready var _warning_bar: Label = $MarginContainer/VBox/WarningBar
@onready var _add_btn: Button = $MarginContainer/VBox/Toolbar/AddBtn
@onready var _refresh_btn: Button = $MarginContainer/VBox/Toolbar/RefreshBtn
@onready var _settings_btn: Button = $MarginContainer/VBox/Toolbar/SettingsBtn
@onready var _empty_state: CenterContainer = $MarginContainer/VBox/ListContainer/EmptyState
@onready var _package_list: ItemList = $MarginContainer/VBox/ListContainer/PackageList
@onready var _actions_bar: HBoxContainer = $MarginContainer/VBox/ActionsBar
@onready var _install_btn: Button = $MarginContainer/VBox/ActionsBar/InstallBtn
@onready var _preview_btn: Button = $MarginContainer/VBox/ActionsBar/PreviewBtn
@onready var _duplicate_btn: Button = $MarginContainer/VBox/ActionsBar/DuplicateBtn
@onready var _remove_btn: Button = $MarginContainer/VBox/ActionsBar/RemoveBtn
@onready var _open_folder_btn: Button = $MarginContainer/VBox/ActionsBar/OpenFolderBtn

var _packages: Array[Dictionary] = []
var _selected_package_index: int = -1
var _pack_dialog: AcceptDialog
var _confirm_remove_dialog: ConfirmationDialog
var _duplicate_id_dialog: AcceptDialog
var _duplicate_id_edit: LineEdit
var _preview_panel: Window
var _settings_dialog: AcceptDialog
var _install_config_dialog: AcceptDialog


func _ready() -> void:
	title = "Package Manager"
	size = Vector2i(900, 600)
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	close_requested.connect(_on_close_requested)
	_add_btn.pressed.connect(_on_add_pressed)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	_settings_btn.pressed.connect(_on_settings_pressed)
	_package_list.item_selected.connect(_on_package_selected)
	_package_list.item_activated.connect(_on_package_activated)
	_install_btn.pressed.connect(_on_install_pressed)
	_preview_btn.pressed.connect(_on_preview_pressed)
	_duplicate_btn.pressed.connect(_on_duplicate_pressed)
	_remove_btn.pressed.connect(_on_remove_pressed)
	_open_folder_btn.pressed.connect(_on_open_folder_pressed)
	_setup_pack_dialog()
	_setup_confirm_dialogs()
	_setup_settings_dialog()
	_setup_install_config_dialog()
	_set_tooltips()
	_refresh_packages()


func _setup_pack_dialog() -> void:
	_pack_dialog = PackDialogScene.instantiate()
	_pack_dialog.transient = false
	# Add to same parent as this window (editor base) so it appears as a separate popup, not embedded
	get_parent().add_child(_pack_dialog)
	_pack_dialog.visible = false
	if _pack_dialog.has_signal("create_package_requested"):
		_pack_dialog.create_package_requested.connect(_on_create_package_requested)
	if _pack_dialog.has_method("setup") and plugin:
		_pack_dialog.setup(plugin)


func _on_add_pressed() -> void:
	if _pack_dialog:
		if _pack_dialog.has_method("clear_form"):
			_pack_dialog.clear_form()
		_pack_dialog.popup_centered_ratio(0.5)
		call_deferred("_keep_manager_visible")
		_update_status("Create a new package")


func _on_refresh_pressed() -> void:
	_refresh_packages()


func _on_settings_pressed() -> void:
	if _settings_dialog:
		_settings_dialog.popup_centered_ratio(0.4)
		call_deferred("_keep_manager_visible")
		_update_status("Configure store path and options")


func _on_package_selected(index: int) -> void:
	_selected_package_index = index
	_update_actions_state()


func _on_package_activated(index: int) -> void:
	_open_preview_for_index(index)


func _on_install_pressed() -> void:
	if _selected_package_index < 0:
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	var store_root: String = pkg["store_root"]
	var package_id: String = pkg["id"]
	var overwrite := _get_overwrite_setting()
	if _install_config_dialog:
		_install_config_dialog.setup(pkg, store_root, package_id, overwrite)
		_install_config_dialog.popup_centered_ratio(0.75)
		call_deferred("_keep_manager_visible")


func _setup_install_config_dialog() -> void:
	_install_config_dialog = InstallConfigDialogScene.instantiate()
	_install_config_dialog.visible = false
	_install_config_dialog.transient = false
	get_parent().add_child(_install_config_dialog)
	if _install_config_dialog.has_signal("install_requested"):
		_install_config_dialog.install_requested.connect(_on_install_config_confirmed)


func _on_install_config_confirmed(install_subpath: String, paths: PackedStringArray, ignore_asset_root: bool) -> void:
	if _selected_package_index < 0:
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	var store_root: String = PackageManagerUtil.globalize(pkg["store_root"])
	var package_id: String = pkg["id"]
	var project_root := ProjectSettings.globalize_path("res://")
	if true:  # debug
		print("[ManagerPopup] install_config_confirmed store_root=%s package_id=%s install_subpath=%s paths_count=%d" % [store_root, package_id, install_subpath, paths.size()])
	_install_btn.disabled = true
	_update_status("Installing...")
	var overwrite := _get_overwrite_setting()
	var result := PackageManagerUtil.install_package_selective(store_root, package_id, project_root, install_subpath, paths, ignore_asset_root, overwrite)
	_install_btn.disabled = false
	if result.get("ok", false):
		_update_status("Installed '%s'." % pkg.get("name", package_id))
		if plugin:
			plugin.get_editor_interface().get_resource_filesystem().scan()
	else:
		_update_status("Failed: %s" % result.get("error", "Unknown error"))


func _on_preview_pressed() -> void:
	if _selected_package_index < 0:
		return
	_open_preview_for_index(_selected_package_index)


func _on_duplicate_pressed() -> void:
	if _selected_package_index < 0:
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	_duplicate_id_edit.text = pkg["id"] + "_copy"
	_duplicate_id_edit.placeholder_text = "new_package_id"
	_duplicate_id_dialog.popup_centered()
	call_deferred("_keep_manager_visible")
	_duplicate_id_edit.grab_focus()


func _on_confirmed_duplicate() -> void:
	var new_id := _duplicate_id_edit.text.strip_edges()
	if new_id.is_empty():
		_update_status("Duplicate cancelled: ID is empty.")
		return
	if _selected_package_index < 0:
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	var store_root: String = pkg["store_root"]
	var source_id: String = pkg["id"]
	var err := PackageManagerUtil.duplicate_package(store_root, source_id, new_id)
	if err == OK:
		_refresh_packages()
		_update_status("Duplicated as \"%s\"." % new_id)
	elif err == ERR_ALREADY_EXISTS:
		_update_status("Error: Package ID \"%s\" already exists." % new_id)
	else:
		_update_status("Failed to duplicate (code %s)." % err)


func _on_remove_pressed() -> void:
	if _selected_package_index < 0:
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	_confirm_remove_dialog.dialog_text = "Remove package \"%s\"? This cannot be undone." % pkg.get("name", pkg["id"])
	_confirm_remove_dialog.popup_centered()
	call_deferred("_keep_manager_visible")


func _on_confirmed_remove() -> void:
	if _selected_package_index < 0:
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	var store_root: String = pkg["store_root"]
	var package_id: String = pkg["id"]
	var err := PackageManagerUtil.remove_package(store_root, package_id)
	if err == OK:
		_refresh_packages()
		_update_status("Removed \"%s\"." % pkg.get("name", package_id))
	else:
		_update_status("Failed to remove package (code %s)." % err)


func _on_open_folder_pressed() -> void:
	if _selected_package_index < 0 or _selected_package_index >= _packages.size():
		return
	var pkg: Dictionary = _packages[_selected_package_index]
	var store_root: String = pkg.get("store_root", "")
	var package_id: String = pkg.get("id", "")
	if store_root.is_empty() or package_id.is_empty():
		return
	var folder_path: String = store_root.path_join(package_id).replace("\\", "/")
	if not DirAccess.dir_exists_absolute(folder_path):
		_update_status("Package folder not found: %s" % folder_path)
		return
	OS.shell_open(folder_path)
	_update_status("Opened folder for \"%s\"." % pkg.get("name", package_id))


func _setup_confirm_dialogs() -> void:
	var parent := get_parent()
	_confirm_remove_dialog = ConfirmationDialog.new()
	_confirm_remove_dialog.title = "Remove Package"
	_confirm_remove_dialog.visible = false
	_confirm_remove_dialog.transient = false
	_confirm_remove_dialog.confirmed.connect(_on_confirmed_remove)
	parent.add_child(_confirm_remove_dialog)

	_duplicate_id_dialog = AcceptDialog.new()
	_duplicate_id_dialog.title = "Duplicate Package"
	_duplicate_id_dialog.visible = false
	_duplicate_id_dialog.transient = false
	var v := VBoxContainer.new()
	var lab := Label.new()
	lab.text = "New package ID:"
	v.add_child(lab)
	_duplicate_id_edit = LineEdit.new()
	_duplicate_id_edit.placeholder_text = "new_package_id"
	_duplicate_id_edit.custom_minimum_size.x = 280
	v.add_child(_duplicate_id_edit)
	_duplicate_id_dialog.add_child(v)
	parent.add_child(_duplicate_id_dialog)
	_duplicate_id_dialog.confirmed.connect(_on_confirmed_duplicate)


func _setup_settings_dialog() -> void:
	_settings_dialog = SettingsDialogScene.instantiate()
	_settings_dialog.visible = false
	_settings_dialog.transient = false
	get_parent().add_child(_settings_dialog)
	if _settings_dialog.has_signal("settings_saved"):
		_settings_dialog.settings_saved.connect(_on_settings_saved)


func _on_settings_saved() -> void:
	_refresh_packages()
	_update_status("Settings saved.")


func _refresh_packages() -> void:
	_update_status("Scanning...")
	_packages.clear()
	_package_list.clear()
	# Will use PackageManagerUtil to scan store
	if has_node("/root/PackageManagerUtil"):
		pass  # placeholder
	var store_path: String = _get_store_path()
	if store_path.is_empty():
		_update_status("No store path configured.")
		if _warning_bar:
			_warning_bar.visible = true
			_warning_bar.text = "Store path not configured. Open Settings to set it."
		return
	var abs_store := PackageManagerUtil.globalize(store_path)
	var parent_exists := DirAccess.dir_exists_absolute(abs_store) or DirAccess.dir_exists_absolute(abs_store.get_base_dir())
	if _warning_bar:
		_warning_bar.visible = !parent_exists
		_warning_bar.text = "Store path not found or not writable. Check Settings."
	var err: Error = _load_packages_from_store(store_path)
	if err != OK:
		_update_status("Error scanning store: %s" % store_path)
		return
	_draw_package_list()
	_update_status("%d package(s)" % _packages.size())
	_selected_package_index = -1
	_update_actions_state()


func _get_store_path() -> String:
	return PackageManagerUtil.get_store_path()


func _get_overwrite_setting() -> bool:
	var cfg := ConfigFile.new()
	var path := ProjectSettings.globalize_path("user://package_manager/settings.cfg")
	if not FileAccess.file_exists(path):
		return false
	if cfg.load(path) != OK:
		return false
	return cfg.get_value("package_manager", "overwrite_existing", false)


func _load_packages_from_store(store_path: String) -> Error:
	_packages.clear()
	for p in PackageManagerUtil.list_packages(store_path):
		_packages.append(p)
	return OK




func _set_tooltips() -> void:
	if _add_btn:
		_add_btn.tooltip_text = "Create a new package from selected files or folders"
	if _refresh_btn:
		_refresh_btn.tooltip_text = "Rescan the package store"
	if _settings_btn:
		_settings_btn.tooltip_text = "Configure store path and options"
	if _install_btn:
		_install_btn.tooltip_text = "Install the selected package into this project"
	if _open_folder_btn:
		_open_folder_btn.tooltip_text = "Open this package's folder in the file manager"
	if _preview_btn:
		_preview_btn.tooltip_text = "Preview package details and manage thumbnails/media"
	if _duplicate_btn:
		_duplicate_btn.tooltip_text = "Duplicate the package with a new ID"
	if _remove_btn:
		_remove_btn.tooltip_text = "Remove the package from the store (cannot be undone)"


func _draw_package_list() -> void:
	_package_list.clear()
	var has_any := _packages.size() > 0
	if _empty_state:
		_empty_state.visible = !has_any
	_package_list.visible = has_any
	for i in range(_packages.size()):
		var p: Dictionary = _packages[i]
		var text := "%s — %s" % [p.get("name", p["id"]), p.get("version", "")]
		var icon: Texture2D = null
		var thumb: String = p.get("thumbnail", "")
		if not thumb.is_empty() and p.has("store_root"):
			var abs_path = p["store_root"].path_join(p["id"]).path_join(thumb)
			if FileAccess.file_exists(abs_path):
				var img := Image.load_from_file(abs_path)
				if img:
					icon = ImageTexture.create_from_image(img)
		_package_list.add_item(text, icon, true)
		_package_list.set_item_tooltip(i, "ID: %s" % p["id"])


func _update_actions_state() -> void:
	var has_selection := _selected_package_index >= 0 and _selected_package_index < _packages.size()
	_install_btn.disabled = !has_selection
	_preview_btn.disabled = !has_selection
	_duplicate_btn.disabled = !has_selection
	_remove_btn.disabled = !has_selection
	_open_folder_btn.disabled = !has_selection


func _open_preview_for_index(index: int) -> void:
	if index < 0 or index >= _packages.size():
		return
	if _preview_panel == null:
		_preview_panel = PreviewPanelScene.instantiate()
		_preview_panel.transient = false
		get_parent().add_child(_preview_panel)
		_preview_panel.visible = false
		_preview_panel.closed.connect(_on_preview_closed)
	var pkg: Dictionary = _packages[index]
	_preview_panel.setup(pkg, plugin)
	_preview_panel.popup_centered(Vector2i(520, 520))
	call_deferred("_keep_manager_visible")


func _on_preview_closed() -> void:
	pass


func _on_create_package_requested(package_id: String, display_name: String, version: String, description: String, paths: PackedStringArray) -> void:
	_add_btn.disabled = true
	_update_status("Packing...")
	var store_path := _get_store_path()
	var err := PackageManagerUtil.create_package(store_path, package_id, display_name, version, description, paths)
	_add_btn.disabled = false
	if err == OK:
		_refresh_packages()
		_update_status("Package '%s' created." % display_name)
	elif err == ERR_ALREADY_EXISTS:
		_update_status("Error: Package ID already exists.")
	else:
		_update_status("Error: Failed to create package (code %s)." % err)


func _on_close_requested() -> void:
	hide()


func _keep_manager_visible() -> void:
	show()


func open_at_screen_with_mouse() -> void:
	show()
	grab_focus()


func _update_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
