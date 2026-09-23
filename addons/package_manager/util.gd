@tool
class_name PackageManagerUtil
extends RefCounted

const _DEBUG_INSTALL := true  # Set to false to disable install/expand debug logs

const SETTINGS_PATH := "user://package_manager/settings.cfg"
const DEFAULT_STORE_PATH := "user://package_manager/packs"

# When set by the plugin, settings and default store use editor-wide paths (shared across all projects).
static var _editor_config_dir: String = ""
static var _editor_data_dir: String = ""

## Call from the plugin so packs and settings use the editor folder (shared across projects).
static func set_editor_paths(config_dir: String, data_dir: String) -> void:
	_editor_config_dir = config_dir.strip_edges().trim_suffix("/")
	_editor_data_dir = data_dir.strip_edges().trim_suffix("/")

static func _get_settings_path() -> String:
	if not _editor_config_dir.is_empty():
		return _editor_config_dir.path_join("package_manager").path_join("settings.cfg")
	return ProjectSettings.globalize_path(SETTINGS_PATH)

static func _get_default_store_path() -> String:
	if not _editor_data_dir.is_empty():
		return _editor_data_dir.path_join("package_manager").path_join("packs")
	return ProjectSettings.globalize_path(DEFAULT_STORE_PATH)

## Returns the default store path (editor or project user). Use for "reset to default".
static func get_default_store_path() -> String:
	return _get_default_store_path()

## Returns the absolute path to the settings file (for loading/saving overwrite etc.).
static func get_settings_file_path() -> String:
	return _get_settings_path()

## Returns the configured store path, or default (editor-wide when set_editor_paths was called).
static func get_store_path() -> String:
	var settings_path := _get_settings_path()
	var default_store := _get_default_store_path()
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(settings_path):
		if cfg.load(settings_path) == OK:
			var saved := cfg.get_value("package_manager", "store_path", "")
			if not saved.is_empty():
				return saved
	return default_store


## Persist store path to settings (editor-wide when set_editor_paths was called).
static func set_store_path(path: String) -> Error:
	var settings_path := _get_settings_path()
	if not _editor_config_dir.is_empty():
		var base := _editor_config_dir.path_join("package_manager")
		if not DirAccess.dir_exists_absolute(base):
			var d := DirAccess.open(_editor_config_dir)
			if d == null:
				return FAILED
			if d.make_dir("package_manager") != OK:
				return FAILED
	else:
		var base := ProjectSettings.globalize_path("user://package_manager")
		if not DirAccess.dir_exists_absolute(base):
			var d := DirAccess.open(ProjectSettings.globalize_path("user://"))
			if d == null:
				return FAILED
			if d.make_dir_recursive("package_manager") != OK:
				return FAILED
	var cfg := ConfigFile.new()
	cfg.set_value("package_manager", "store_path", path)
	return cfg.save(settings_path)


## Globalize path (user:// or res://) to absolute.
static func globalize(p: String) -> String:
	if p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	return p


## Zip a folder recursively to a .zip file (absolute paths). Returns OK on success.
static func _zip_folder(src_dir_abs: String, zip_path_abs: String) -> Error:
	if not DirAccess.dir_exists_absolute(src_dir_abs):
		return ERR_FILE_NOT_FOUND
	var parent := zip_path_abs.get_base_dir()
	if not parent.is_empty() and _ensure_dir_absolute(parent) != OK:
		return FAILED
	var zipper := ZIPPacker.new()
	if zipper.open(zip_path_abs, ZIPPacker.APPEND_CREATE) != OK:
		return FAILED
	var err := _zip_folder_recursive(zipper, src_dir_abs, "")
	zipper.close()
	return err


static func _zip_folder_recursive(zipper: ZIPPacker, abs_dir: String, rel_prefix: String) -> Error:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return FAILED
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		if n == ".zip":
			n = dir.get_next()
			continue
		var rel_path := rel_prefix + n if rel_prefix.is_empty() else rel_prefix + "/" + n
		var full := abs_dir.path_join(n)
		if dir.current_is_dir():
			var e := _zip_folder_recursive(zipper, full, rel_path)
			if e != OK:
				dir.list_dir_end()
				return e
		else:
			zipper.start_file(rel_path)
			var data := FileAccess.get_file_as_bytes(full)
			if data == null:
				dir.list_dir_end()
				return FAILED
			zipper.write_file(data)
			zipper.close_file()
		n = dir.get_next()
	dir.list_dir_end()
	return OK


## Unzip a .zip file to a directory (absolute paths). Creates dest_dir if needed.
static func _unzip_to(zip_path_abs: String, dest_dir_abs: String) -> Error:
	if not FileAccess.file_exists(zip_path_abs):
		return ERR_FILE_NOT_FOUND
	dest_dir_abs = dest_dir_abs.replace("\\", "/").strip_edges().trim_suffix("/")
	if _ensure_dir_absolute(dest_dir_abs) != OK:
		return FAILED
	var reader := ZIPReader.new()
	if reader.open(zip_path_abs) != OK:
		return FAILED
	var files := reader.get_files()
	for raw_path in files:
		var file_path := str(raw_path).replace("\\", "/").strip_edges().lstrip("/")
		if file_path.is_empty():
			continue
		if file_path == ".zip" or file_path.get_file() == ".zip":
			continue
		if file_path.ends_with("/"):
			var dir_path := dest_dir_abs + "/" + file_path.trim_suffix("/")
			_ensure_dir_absolute(dir_path)
			continue
		# Build output path with forward slashes so FileAccess works on all platforms
		var out_path := (dest_dir_abs + "/" + file_path).replace("//", "/")
		var out_dir := out_path.get_base_dir().replace("\\", "/")
		if not out_dir.is_empty() and _ensure_dir_absolute(out_dir) != OK:
			reader.close()
			return FAILED
		var data := reader.read_file(raw_path)
		if data == null:
			data = PackedByteArray()
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			reader.close()
			return FAILED
		f.store_buffer(data)
		f.close()
	reader.close()
	return OK


## Extract a single file from a zip to a destination path. Creates parent dir of dest_file_abs if needed.
static func _extract_single_from_zip(zip_path_abs: String, entry_name: String, dest_file_abs: String) -> Error:
	if not FileAccess.file_exists(zip_path_abs):
		return ERR_FILE_NOT_FOUND
	var reader := ZIPReader.new()
	if reader.open(zip_path_abs) != OK:
		return FAILED
	if not reader.file_exists(entry_name):
		reader.close()
		return ERR_FILE_NOT_FOUND
	var data := reader.read_file(entry_name)
	reader.close()
	if data == null:
		data = PackedByteArray()
	dest_file_abs = dest_file_abs.replace("\\", "/").strip_edges()
	var out_dir := dest_file_abs.get_base_dir()
	if not out_dir.is_empty() and _ensure_dir_absolute(out_dir) != OK:
		return FAILED
	var f := FileAccess.open(dest_file_abs, FileAccess.WRITE)
	if f == null:
		return FAILED
	f.store_buffer(data)
	f.close()
	return OK


## Copy a file or directory recursively from src to dst (absolute paths).
static func copy_recursive(src: String, dst: String) -> Error:
	if not FileAccess.file_exists(src) and not DirAccess.dir_exists_absolute(src):
		return ERR_FILE_NOT_FOUND
	if DirAccess.dir_exists_absolute(src):
		return _copy_dir_recursive(src, dst)
	else:
		var dir := dst.get_base_dir()
		if _ensure_dir_absolute(dir) != OK:
			return FAILED
		return OK if DirAccess.copy_absolute(src, dst) == OK else FAILED


static func _copy_dir_recursive(src: String, dst: String) -> Error:
	var dir := DirAccess.open(src)
	if dir == null:
		return FAILED
	if not DirAccess.dir_exists_absolute(dst):
		var parent := dst.get_base_dir()
		if not DirAccess.dir_exists_absolute(parent):
			var err := _copy_dir_recursive(src.get_base_dir(), parent)
			if err != OK:
				return err
		var d := DirAccess.open(parent)
		if d == null:
			return FAILED
		if d.make_dir(dst.get_file()) != OK:
			return FAILED
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		var src_child := src.path_join(n)
		var dst_child := dst.path_join(n)
		if dir.current_is_dir():
			var e := _copy_dir_recursive(src_child, dst_child)
			if e != OK:
				dir.list_dir_end()
				return e
		else:
			if DirAccess.copy_absolute(src_child, dst_child) != OK:
				dir.list_dir_end()
				return FAILED
		n = dir.get_next()
	dir.list_dir_end()
	return OK


## List all package ids and manifest paths in the store.
static func list_packages(store_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var abs_path := globalize(store_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return out
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var sub := dir.get_next()
	while sub != "":
		if dir.current_is_dir() and sub != "." and sub != "..":
			var manifest_path := abs_path.path_join(sub).path_join("manifest.cfg")
			if FileAccess.file_exists(manifest_path):
				var cfg := ConfigFile.new()
				if cfg.load(manifest_path) == OK:
					var store_root := manifest_path.get_base_dir().get_base_dir()
					out.append({
						"id": sub,
						"name": cfg.get_value("package", "name", sub),
						"version": cfg.get_value("package", "version", ""),
						"store_root": store_root,
						"thumbnail": cfg.get_value("package", "thumbnail", ""),
						"media": cfg.get_value("package", "media", []),
					})
		sub = dir.get_next()
	dir.list_dir_end()
	return out


## Media file extensions allowed for thumbnails and media.
const MEDIA_IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const MEDIA_VIDEO_EXTENSIONS := ["webm", "ogv", "mp4"]


static func is_media_image(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in MEDIA_IMAGE_EXTENSIONS


static func is_media_video(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext in MEDIA_VIDEO_EXTENSIONS


static func is_media_file(path: String) -> bool:
	return is_media_image(path) or is_media_video(path)


## Load full manifest for a package (includes paths).
static func load_manifest(store_root: String, package_id: String) -> Dictionary:
	var manifest_path := globalize(store_root).path_join(package_id).path_join("manifest.cfg")
	if not FileAccess.file_exists(manifest_path):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return {}
	var paths_var := cfg.get_value("package", "paths", [])
	var paths: PackedStringArray = PackedStringArray()
	if paths_var is Array:
		for p in paths_var:
			paths.append(str(p))
	elif paths_var is PackedStringArray:
		paths = paths_var
	if paths.is_empty():
		paths = list_content_paths(globalize(store_root), package_id)
	return {
		"id": package_id,
		"name": cfg.get_value("package", "name", package_id),
		"version": cfg.get_value("package", "version", ""),
		"store_root": globalize(store_root),
		"thumbnail": cfg.get_value("package", "thumbnail", ""),
		"media": cfg.get_value("package", "media", []),
		"paths": paths,
	}



## List all relative paths under content/ for a package (for old packages without paths in manifest).
static func list_content_paths(store_root_globalized: String, package_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var content_dir := store_root_globalized.path_join(package_id).path_join("content")
	if not DirAccess.dir_exists_absolute(content_dir):
		return out
	_list_content_paths_recursive(content_dir, "", out)
	return out


static func _list_content_paths_recursive(abs_dir: String, rel_prefix: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		var rel := rel_prefix + n if rel_prefix.is_empty() else rel_prefix + "/" + n
		var full := abs_dir.path_join(n)
		if dir.current_is_dir():
			_list_content_paths_recursive(full, rel, out)
		else:
			# Folders are stored as .zip; expose as path without .zip so install/UI see one folder entry
			if n.ends_with(".zip"):
				out.append(rel.substr(0, rel.length() - 4))
			else:
				out.append(rel)
		n = dir.get_next()
	dir.list_dir_end()


## Install (unpack) a package into the project. store_root is the package's store root path.
static func install_package(store_root_globalized: String, package_id: String, project_res_globalized: String, overwrite: bool) -> Dictionary:
	var manifest := load_manifest(store_root_globalized, package_id)
	if manifest.is_empty():
		return {"ok": false, "error": "Manifest not found"}
	var paths: PackedStringArray = manifest.get("paths", PackedStringArray())
	return install_package_selective(store_root_globalized, package_id, project_res_globalized, "", paths, false, overwrite)


## Install selected paths into project. install_subpath is relative to project root (e.g. "addons/MyAddon"). paths_to_install: which manifest paths to copy. ignore_asset_root: strip first path segment from each path when installing.
static func install_package_selective(store_root_globalized: String, package_id: String, project_res_globalized: String, install_subpath: String, paths_to_install: PackedStringArray, ignore_asset_root: bool, overwrite: bool) -> Dictionary:
	var content_dir := store_root_globalized.path_join(package_id).path_join("content").replace("\\", "/")
	var base := project_res_globalized.replace("\\", "/").strip_edges().trim_suffix("/")
	if not install_subpath.is_empty():
		base = (base + "/" + install_subpath.replace("\\", "/").strip_edges().trim_suffix("/")).replace("//", "/")
	if _DEBUG_INSTALL:
		print("[PackageManagerUtil] install_package_selective content_dir=%s base=%s paths_count=%d" % [content_dir, base, paths_to_install.size()])
	for rel_path in paths_to_install:
		rel_path = rel_path.replace("\\", "/").strip_edges()
		if rel_path.is_empty():
			continue
		var install_path := rel_path
		if ignore_asset_root:
			var idx := rel_path.find("/")
			if idx >= 0:
				install_path = rel_path.substr(idx + 1)
			else:
				install_path = rel_path.get_file()
		var dst := (base + "/" + install_path).replace("//", "/")
		var zip_src := (content_dir + "/" + rel_path + ".zip").replace("//", "/")
		var dir_or_file_src := (content_dir + "/" + rel_path).replace("//", "/")
		var zip_ok := FileAccess.file_exists(zip_src)
		var dir_ok := DirAccess.dir_exists_absolute(dir_or_file_src)
		var file_ok := FileAccess.file_exists(dir_or_file_src)
		if _DEBUG_INSTALL:
			print("  rel_path=%s -> dst=%s zip_ok=%s dir_ok=%s file_ok=%s" % [rel_path, dst, zip_ok, dir_ok, file_ok])
		if zip_ok:
			# Whole folder zip: extract all
			if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
				if not overwrite:
					return {"ok": false, "error": "Folder already exists (enable overwrite): %s" % install_path}
			if _ensure_dir_absolute(dst) != OK:
				return {"ok": false, "error": "Failed to create destination: %s" % install_path}
			var e := _unzip_to(zip_src, dst)
			if _DEBUG_INSTALL:
				print("    _unzip_to(%s, %s) -> %s" % [zip_src, dst, e])
			if e != OK:
				return {"ok": false, "error": "Failed to extract %s (code %s)" % [install_path, e]}
		elif file_ok and rel_path.ends_with("/.zip"):
			# Store has a dir with a file named .zip (e.g. content/Test/.zip) — extract zip into destination folder
			var dst_dir := (base + "/" + install_path.get_base_dir()).replace("//", "/")
			if FileAccess.file_exists(dst_dir) or DirAccess.dir_exists_absolute(dst_dir):
				if not overwrite:
					return {"ok": false, "error": "Folder already exists (enable overwrite): %s" % install_path.get_base_dir()}
			if _ensure_dir_absolute(dst_dir) != OK:
				return {"ok": false, "error": "Failed to create destination: %s" % install_path.get_base_dir()}
			var e := _unzip_to(dir_or_file_src, dst_dir)
			if _DEBUG_INSTALL:
				print("    _unzip_to(.zip file) (%s, %s) -> %s" % [dir_or_file_src, dst_dir, e])
			if e != OK:
				return {"ok": false, "error": "Failed to extract %s (code %s)" % [install_path, e]}
		elif dir_ok or file_ok:
			# Direct file or dir in content
			if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
				if not overwrite:
					return {"ok": false, "error": "File or folder already exists (enable overwrite): %s" % install_path}
			var e := copy_recursive(dir_or_file_src, dst)
			if _DEBUG_INSTALL:
				print("    copy_recursive -> %s" % e)
			if e != OK:
				return {"ok": false, "error": "Failed to copy %s (code %s)" % [install_path, e]}
		else:
			# Path may be a file inside a zip: either parent.zip (e.g. content/Test.zip) or parent/.zip (e.g. content/Test/.zip)
			var parent := rel_path.get_base_dir()
			var found_zip := false
			while not parent.is_empty():
				var parent_zip := (content_dir + "/" + parent + ".zip").replace("//", "/")
				var parent_dot_zip := (content_dir + "/" + parent + "/.zip").replace("//", "/")
				var zip_path_to_use := ""
				if FileAccess.file_exists(parent_zip):
					zip_path_to_use = parent_zip
				elif FileAccess.file_exists(parent_dot_zip):
					zip_path_to_use = parent_dot_zip
				if not zip_path_to_use.is_empty():
					var entry_name := rel_path.substr(parent.length() + 1)
					if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
						if not overwrite:
							return {"ok": false, "error": "File already exists (enable overwrite): %s" % install_path}
					var e := _extract_single_from_zip(zip_path_to_use, entry_name, dst)
					if _DEBUG_INSTALL:
						print("    extract from zip %s entry=%s -> %s" % [zip_path_to_use, entry_name, e])
					if e != OK:
						return {"ok": false, "error": "Failed to extract %s (code %s)" % [install_path, e]}
					found_zip = true
					break
				parent = parent.get_base_dir()
			if _DEBUG_INSTALL and not found_zip:
				print("    no zip found for path, skipping")
			if not found_zip:
				continue
	if _DEBUG_INSTALL:
		print("  install_package_selective done ok=true")
	return {"ok": true}


## Returns the full list of relative paths that will be installed for the given paths (expands zips/dirs into file list). Used for installation preview.
static func get_expanded_install_paths(store_root_globalized: String, package_id: String, paths: PackedStringArray) -> PackedStringArray:
	var content_dir := (store_root_globalized.path_join(package_id).path_join("content")).replace("\\", "/")
	var out: PackedStringArray = []
	if _DEBUG_INSTALL:
		print("[PackageManagerUtil] get_expanded_install_paths content_dir=%s paths_count=%d" % [content_dir, paths.size()])
	for rel_path in paths:
		rel_path = rel_path.replace("\\", "/").strip_edges().trim_suffix("/")
		if rel_path.is_empty():
			continue
		var zip_path := (content_dir + "/" + rel_path + ".zip").replace("//", "/")
		var dir_or_file := (content_dir + "/" + rel_path).replace("//", "/")
		var zip_exists := FileAccess.file_exists(zip_path)
		var dir_exists := DirAccess.dir_exists_absolute(dir_or_file)
		var file_exists := FileAccess.file_exists(dir_or_file)
		if _DEBUG_INSTALL:
			print("  rel_path=%s zip=%s zip_exists=%s dir_exists=%s file_exists=%s" % [rel_path, zip_path, zip_exists, dir_exists, file_exists])
		if zip_exists:
			var reader := ZIPReader.new()
			if reader.open(zip_path) == OK:
				var files := reader.get_files()
				if _DEBUG_INSTALL:
					print("    zip opened, %d entries" % files.size())
				for raw_fp in files:
					var file_path := str(raw_fp).replace("\\", "/").strip_edges().lstrip("/")
					if file_path.is_empty() or file_path.ends_with("/"):
						continue
					if file_path == ".zip" or file_path.get_file() == ".zip":
						continue
					var full := (rel_path + "/" + file_path).replace("//", "/")
					out.append(full)
				reader.close()
			elif _DEBUG_INSTALL:
				print("    zip open FAILED")
		elif dir_exists:
			_expand_dir_paths(dir_or_file, rel_path, out)
			if _DEBUG_INSTALL:
				print("    expanded dir, out now has %d paths" % out.size())
		elif file_exists:
			out.append(rel_path)
			if _DEBUG_INSTALL:
				print("    single file appended")
	if _DEBUG_INSTALL:
		print("  get_expanded_install_paths result count=%d" % out.size())
	return out


static func _expand_dir_paths(abs_dir: String, rel_prefix: String, out: PackedStringArray) -> void:
	abs_dir = abs_dir.replace("\\", "/").strip_edges().trim_suffix("/")
	var dir := DirAccess.open(abs_dir)
	if _DEBUG_INSTALL:
		print("    _expand_dir_paths abs_dir=%s rel_prefix=%s dir_valid=%s" % [abs_dir, rel_prefix, dir != null])
	if dir == null:
		return
	var err := dir.list_dir_begin()
	if _DEBUG_INSTALL:
		print("      list_dir_begin err=%s" % err)
	var n := dir.get_next()
	var entry_count := 0
	while n != "":
		entry_count += 1
		var is_dir := dir.current_is_dir()
		if _DEBUG_INSTALL and entry_count <= 15:
			print("      entry: name=%s is_dir=%s" % [n, is_dir])
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		var rel := (rel_prefix + "/" + n).replace("//", "/") if not rel_prefix.is_empty() else n
		var full := abs_dir.path_join(n).replace("\\", "/")
		if is_dir:
			_expand_dir_paths(full, rel, out)
		elif n == ".zip":
			# Directory contains a single file named .zip — treat as archive and expand its contents for preview/install
			_expand_zip_entries_into_paths(full, rel_prefix, out)
		else:
			out.append(rel)
		n = dir.get_next()
	dir.list_dir_end()
	if _DEBUG_INSTALL:
		print("      _expand_dir_paths total entries=%d out.size() now=%d" % [entry_count, out.size()])


## When a store directory contains a file named .zip, expand that zip's entries into out with rel_prefix (e.g. "Test" -> "Test/icon.svg").
static func _expand_zip_entries_into_paths(zip_path_abs: String, rel_prefix: String, out: PackedStringArray) -> void:
	var reader := ZIPReader.new()
	if reader.open(zip_path_abs) != OK:
		return
	for raw_fp in reader.get_files():
		var file_path := str(raw_fp).replace("\\", "/").strip_edges().lstrip("/")
		if file_path.is_empty() or file_path.ends_with("/"):
			continue
		if file_path == ".zip" or file_path.get_file() == ".zip":
			continue
		var full := (rel_prefix + "/" + file_path).replace("//", "/") if not rel_prefix.is_empty() else file_path
		out.append(full)
	reader.close()


## Count how many paths would conflict (already exist) in project. Returns { "count": N, "paths": [...] }.
static func count_conflicts(project_res_globalized: String, install_subpath: String, paths: PackedStringArray, ignore_asset_root: bool) -> Dictionary:
	var base := project_res_globalized
	if not install_subpath.is_empty():
		base = base.path_join(install_subpath.replace("\\", "/").strip_edges().trim_suffix("/"))
	var conflicting: Array = []
	for rel_path in paths:
		rel_path = rel_path.replace("\\", "/").strip_edges()
		if rel_path.is_empty():
			continue
		var install_path := rel_path
		if ignore_asset_root:
			var idx := rel_path.find("/")
			if idx >= 0:
				install_path = rel_path.substr(idx + 1)
			else:
				install_path = rel_path.get_file()
		var dst := base.path_join(install_path)
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			conflicting.append(install_path)
	return {"count": conflicting.size(), "paths": conflicting}


## Ensure package has a media/ directory; return path to it.
static func ensure_media_dir(store_root_globalized: String, package_id: String) -> String:
	var pkg_dir := store_root_globalized.path_join(package_id)
	var media_dir := pkg_dir.path_join("media")
	if not DirAccess.dir_exists_absolute(media_dir):
		var d := DirAccess.open(pkg_dir)
		if d == null:
			return ""
		if d.make_dir("media") != OK:
			return ""
	return media_dir


## Add a media file to a package (copy from source path). Returns the relative path under media/ or empty on failure.
static func add_media_file(store_root_globalized: String, package_id: String, source_absolute_path: String) -> String:
	if not is_media_file(source_absolute_path):
		return ""
	var media_dir := ensure_media_dir(store_root_globalized, package_id)
	if media_dir.is_empty():
		return ""
	var fname := source_absolute_path.get_file()
	var dst := media_dir.path_join(fname)
	if DirAccess.copy_absolute(source_absolute_path, dst) != OK:
		return ""
	var rel_path := "media/%s" % fname
	_append_media_in_manifest(store_root_globalized, package_id, rel_path)
	return rel_path


static func _append_media_in_manifest(store_root_globalized: String, package_id: String, rel_path: String) -> void:
	var manifest_path := store_root_globalized.path_join(package_id).path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return
	var media: Array = Array(cfg.get_value("package", "media", []))
	if rel_path in media:
		return
	media.append(rel_path)
	cfg.set_value("package", "media", media)
	cfg.save(manifest_path)


## Remove a media entry from package and delete the file.
static func remove_media_file(store_root_globalized: String, package_id: String, rel_path: String) -> Error:
	var manifest_path := store_root_globalized.path_join(package_id).path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return FAILED
	var media: Array = Array(cfg.get_value("package", "media", []))
	if rel_path in media:
		media.erase(rel_path)
	cfg.set_value("package", "media", media)
	var thumb := cfg.get_value("package", "thumbnail", "")
	if thumb == rel_path:
		cfg.set_value("package", "thumbnail", "")
	cfg.save(manifest_path)
	var abs_path := store_root_globalized.path_join(package_id).path_join(rel_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	return OK


## Set the package thumbnail to a media path (must be in media list or added).
static func set_package_thumbnail(store_root_globalized: String, package_id: String, rel_path: String) -> Error:
	var root := globalize(store_root_globalized)
	var manifest_path := root.path_join(package_id).path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return FAILED
	cfg.set_value("package", "thumbnail", rel_path)
	return OK if cfg.save(manifest_path) == OK else FAILED


## Remove a package folder from the store (delete recursively).
static func remove_package(store_root_globalized: String, package_id: String) -> Error:
	var pkg_dir := store_root_globalized.path_join(package_id)
	if not DirAccess.dir_exists_absolute(pkg_dir):
		return ERR_DOES_NOT_EXIST
	return _remove_dir_recursive(pkg_dir)


static func _remove_dir_recursive(path: String) -> Error:
	var dir := DirAccess.open(path)
	if dir == null:
		return FAILED
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == "..":
			n = dir.get_next()
			continue
		var child := path.path_join(n)
		if dir.current_is_dir():
			var e := _remove_dir_recursive(child)
			if e != OK:
				dir.list_dir_end()
				return e
		else:
			if DirAccess.remove_absolute(child) != OK:
				dir.list_dir_end()
				return FAILED
		n = dir.get_next()
	dir.list_dir_end()
	return OK if DirAccess.remove_absolute(path) == OK else FAILED


## Duplicate a package to a new id (copies folder and updates manifest).
static func duplicate_package(store_root_globalized: String, source_id: String, new_id: String) -> Error:
	var src_dir := store_root_globalized.path_join(source_id)
	var dst_dir := store_root_globalized.path_join(new_id)
	if DirAccess.dir_exists_absolute(dst_dir):
		return ERR_ALREADY_EXISTS
	if not DirAccess.dir_exists_absolute(src_dir):
		return ERR_DOES_NOT_EXIST
	var e := _copy_dir_recursive(src_dir, dst_dir)
	if e != OK:
		return e
	var manifest_path := dst_dir.path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	if cfg.load(manifest_path) != OK:
		return FAILED
	cfg.set_value("package", "id", new_id)
	cfg.set_value("package", "name", cfg.get_value("package", "name", source_id) + " (copy)")
	return OK if cfg.save(manifest_path) == OK else FAILED


## Ensure a directory and all parents exist (absolute path). Returns OK on success.
static func _ensure_dir_absolute(path: String) -> Error:
	path = path.replace("\\", "/").strip_edges().trim_suffix("/")
	if path.is_empty():
		return OK
	if DirAccess.dir_exists_absolute(path):
		return OK
	var parent := path.get_base_dir()
	if parent != path and not parent.is_empty():
		var err := _ensure_dir_absolute(parent)
		if err != OK:
			return err
	var d := DirAccess.open(parent)
	if d == null:
		return FAILED
	var name := path.get_file()
	var err := d.make_dir(name)
	if err == OK:
		return OK
	# Directory may already exist (path normalization, race, or make_dir returned ERR_ALREADY_EXISTS)
	if DirAccess.dir_exists_absolute(path):
		return OK
	return err


## Create package directory layout and write manifest. paths are relative to project res://.
static func create_package(store_path: String, package_id: String, display_name: String, version: String, description: String, paths: PackedStringArray) -> Error:
	var root := globalize(store_path)
	var pkg_dir := root.path_join(package_id)
	var content_dir := pkg_dir.path_join("content")
	if DirAccess.dir_exists_absolute(pkg_dir):
		return ERR_ALREADY_EXISTS
	if _ensure_dir_absolute(root) != OK:
		return FAILED
	var d := DirAccess.open(root)
	if d == null:
		return FAILED
	if d.make_dir(package_id) != OK:
		return FAILED
	if d.change_dir(package_id) != OK:
		return FAILED
	if d.make_dir("content") != OK:
		return FAILED
	var project_root := ProjectSettings.globalize_path("res://")
	for rel_path in paths:
		rel_path = rel_path.replace("\\", "/").strip_edges()
		if rel_path.is_empty():
			continue
		var src := project_root.path_join(rel_path)
		if DirAccess.dir_exists_absolute(src):
			var zip_dst := content_dir.path_join(rel_path + ".zip")
			if _ensure_dir_absolute(zip_dst.get_base_dir()) != OK:
				return FAILED
			var e := _zip_folder(src, zip_dst)
			if e != OK:
				return e
		else:
			var dst := content_dir.path_join(rel_path)
			var e := copy_recursive(src, dst)
			if e != OK:
				return e
	var manifest_path := pkg_dir.path_join("manifest.cfg")
	var cfg := ConfigFile.new()
	cfg.set_value("package", "id", package_id)
	cfg.set_value("package", "name", display_name if display_name else package_id)
	cfg.set_value("package", "version", version)
	cfg.set_value("package", "description", description)
	cfg.set_value("package", "paths", Array(paths))
	cfg.set_value("package", "thumbnail", "")
	cfg.set_value("package", "media", [])
	cfg.set_value("package", "created_at", Time.get_datetime_string_from_system())
	if cfg.save(manifest_path) != OK:
		return FAILED
	return OK
