@tool
extends PanelContainer

signal files_dropped(files: PackedStringArray)

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if data is Dictionary:
		if data.get("type") == "files":
			return true
		if data.has("files"):
			return true
	return false


func _drop_data(_position: Vector2, data: Variant) -> void:
	var files: PackedStringArray = PackedStringArray()
	if data is Dictionary:
		if data.get("type") == "files":
			var f = data.get("files")
			if f is PackedStringArray:
				files = f
			elif f is Array:
				for p in f:
					files.append(str(p))
		elif data.has("files"):
			var f = data.get("files")
			if f is PackedStringArray:
				files = f
			elif f is Array:
				for p in f:
					files.append(str(p))
	if files.size() > 0:
		files_dropped.emit(files)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		modulate = Color(1.2, 1.2, 1.2)
	elif what == NOTIFICATION_DRAG_END:
		modulate = Color(1, 1, 1)
