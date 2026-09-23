@tool
extends EditorPlugin

const ManagerPopup = preload("res://addons/package_manager/manager_popup.tscn")

var _manager_popup: Window
var _menu_button: MenuButton


func _enter_tree() -> void:
	var ep := get_editor_interface().get_editor_paths()
	PackageManagerUtil.set_editor_paths(ep.get_config_dir(), ep.get_data_dir())

	_manager_popup = ManagerPopup.instantiate()
	_manager_popup.plugin = self
	_manager_popup.visible = false
	EditorInterface.get_base_control().add_child(_manager_popup)

	_menu_button = MenuButton.new()
	_menu_button.text = "Package Manager"
	var popup: PopupMenu = _menu_button.get_popup()
	popup.add_item("Open Package Manager", 0)
	popup.id_pressed.connect(_on_menu_id_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, _menu_button)


func _exit_tree() -> void:
	if _menu_button:
		remove_control_from_container(CONTAINER_TOOLBAR, _menu_button)
		_menu_button.queue_free()
		_menu_button = null
	if _manager_popup:
		_manager_popup.queue_free()
		_manager_popup = null


func _on_menu_id_pressed(id: int) -> void:
	if id == 0:
		_on_menu_open_manager()


func _on_menu_open_manager() -> void:
	if _manager_popup:
		_manager_popup.open_at_screen_with_mouse()
