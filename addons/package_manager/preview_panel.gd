@tool
extends Window

signal closed

var _package: Dictionary
var _plugin: EditorPlugin
var _file_dialog: EditorFileDialog

@onready var _name_label: Label = $MarginContainer/VBox/Header/NameLabel
@onready var _meta_label: Label = $MarginContainer/VBox/Header/MetaLabel
@onready var _thumbnail_rect: TextureRect = $MarginContainer/VBox/ThumbnailRow/ThumbnailRect
@onready var _paths_list: ItemList = $MarginContainer/VBox/PathsSection/PathsList
@onready var _description_label: Label = $MarginContainer/VBox/DescriptionLabel
@onready var _media_drop_zone: PanelContainer = $MarginContainer/VBox/MediaSection/MediaDropZone
@onready var _media_list: ItemList = $MarginContainer/VBox/MediaSection/MediaList
@onready var _add_media_btn: Button = $MarginContainer/VBox/MediaSection/MediaButtons/AddMediaBtn
@onready var _paste_media_btn: Button = $MarginContainer/VBox/MediaSection/MediaButtons/PasteMediaBtn
@onready var _set_thumbnail_btn: Button = $MarginContainer/VBox/MediaSection/MediaItemButtons/SetThumbnailBtn
@onready var _remove_media_btn: Button = $MarginContainer/VBox/MediaSection/MediaItemButtons/RemoveMediaBtn


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	if _media_drop_zone.has_signal("files_dropped"):
		_media_drop_zone.files_dropped.connect(_on_files_dropped)
	_add_media_btn.pressed.connect(_on_add_media_pressed)
	_paste_media_btn.pressed.connect(_on_paste_media_pressed)
	_set_thumbnail_btn.pressed.connect(_on_set_thumbnail_pressed)
	_remove_media_btn.pressed.connect(_on_remove_media_pressed)
	_media_list.item_selected.connect(_on_media_item_selected)


func setup(package: Dictionary, plugin_ref: EditorPlugin = null) -> void:
	_package = package
	_plugin = plugin_ref
	title = "Preview: %s" % package.get("name", package["id"])
	_name_label.text = package.get("name", package["id"])
	_meta_label.text = "ID: %s  |  Version: %s" % [package["id"], package.get("version", "")]
	_description_label.text = package.get("description", "")
	_description_label.visible = not _description_label.text.is_empty()
	_paths_list.clear()
	var paths: Array = package.get("paths", [])
	if paths.is_empty() and package.has("store_root"):
		var manifest := PackageManagerUtil.load_manifest(package["store_root"], package["id"])
		paths = Array(manifest.get("paths", []))
	for p in paths:
		_paths_list.add_item(str(p))
	_refresh_thumbnail()
	_refresh_media_list()


func _refresh_thumbnail() -> void:
	var thumb_path: String = _package.get("thumbnail", "")
	if thumb_path.is_empty() or not _package.has("store_root"):
		_thumbnail_rect.texture = null
		return
	var abs_path = _package["store_root"].path_join(_package["id"]).path_join(thumb_path)
	if not FileAccess.file_exists(abs_path):
		_thumbnail_rect.texture = null
		return
	var img := Image.load_from_file(abs_path)
	if img:
		_thumbnail_rect.texture = ImageTexture.create_from_image(img)
	else:
		_thumbnail_rect.texture = null


func _refresh_media_list() -> void:
	_media_list.clear()
	var media: Array = Array(_package.get("media", []))
	for m in media:
		_media_list.add_item(str(m))
	_update_media_buttons_state()


func _update_media_buttons_state() -> void:
	var sel := _media_list.get_selected_items()
	var has_sel := sel.size() > 0
	_set_thumbnail_btn.disabled = !has_sel
	_remove_media_btn.disabled = !has_sel


func _on_files_dropped(files: PackedStringArray) -> void:
	_add_media_files(files)


func _on_add_media_pressed() -> void:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
		_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_file_dialog.files_selected.connect(_on_media_files_selected)
		add_child(_file_dialog)
	_file_dialog.clear_filters()
	_file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp", "Images")
	_file_dialog.add_filter("*.webm, *.ogv, *.mp4", "Videos")
	_file_dialog.add_filter("*.*", "All files")
	_file_dialog.title = "Select media files"
	_file_dialog.popup_centered_ratio(0.5)


func _on_media_files_selected(paths: PackedStringArray) -> void:
	_add_media_files(paths)


func _on_paste_media_pressed() -> void:
	var clip := DisplayServer.clipboard_get()
	if clip.is_empty():
		return
	var paths: PackedStringArray = PackedStringArray()
	for line in clip.split("\n"):
		var p := str(line).strip_edges()
		if p.contains("://") or p.begins_with("/") or (p.length() >= 2 and p[1] == ":"):
			if FileAccess.file_exists(p) and PackageManagerUtil.is_media_file(p):
				paths.append(p)
	if paths.size() > 0:
		_add_media_files(paths)


func _add_media_files(source_paths: PackedStringArray) -> void:
	if not _package.has("store_root"):
		return
	var store_root: String = _package["store_root"]
	var package_id: String = _package["id"]
	var added := 0
	for src in source_paths:
		var abs_src := src
		if abs_src.begins_with("res://"):
			abs_src = ProjectSettings.globalize_path(abs_src)
		if not FileAccess.file_exists(abs_src):
			continue
		var rel := PackageManagerUtil.add_media_file(store_root, package_id, abs_src)
		if not rel.is_empty():
			added += 1
	if added > 0:
		var manifest := PackageManagerUtil.load_manifest(store_root, package_id)
		_package["thumbnail"] = manifest.get("thumbnail", "")
		_package["media"] = manifest.get("media", [])
		_refresh_thumbnail()
		_refresh_media_list()


func _on_media_item_selected(_index: int) -> void:
	_update_media_buttons_state()


func _on_set_thumbnail_pressed() -> void:
	var sel := _media_list.get_selected_items()
	if sel.is_empty():
		return
	var rel_path: String = _media_list.get_item_text(sel[0])
	var store_root: String = _package["store_root"]
	var package_id: String = _package["id"]
	if PackageManagerUtil.set_package_thumbnail(store_root, package_id, rel_path) == OK:
		_package["thumbnail"] = rel_path
		_refresh_thumbnail()


func _on_remove_media_pressed() -> void:
	var sel := _media_list.get_selected_items()
	if sel.is_empty():
		return
	var rel_path: String = _media_list.get_item_text(sel[0])
	var store_root: String = _package["store_root"]
	var package_id: String = _package["id"]
	if PackageManagerUtil.remove_media_file(store_root, package_id, rel_path) == OK:
		var manifest := PackageManagerUtil.load_manifest(store_root, package_id)
		_package["thumbnail"] = manifest.get("thumbnail", "")
		_package["media"] = manifest.get("media", [])
		_refresh_thumbnail()
		_refresh_media_list()


func _on_close_requested() -> void:
	closed.emit()
	hide()
