extends Node3D
## Captures OpenXR hand joints into SkeletonProfileHumanoid bone tracks.

const SAMPLE_RATE := 30.0
const LEFT_TRACKER := &"/user/hand_tracker/left"
const RIGHT_TRACKER := &"/user/hand_tracker/right"

## OpenXR joint indices follow XRHandTracker.HandJoint. Each record maps the
## OpenXR joint to a Godot Humanoid hand bone and its source parent joint.
const HAND_BONES := [
	{"side": "Left", "joint": 1, "parent": -1, "bone": "LeftHand"},
	{"side": "Left", "joint": 2, "parent": 1, "bone": "LeftThumbMetacarpal"},
	{"side": "Left", "joint": 3, "parent": 2, "bone": "LeftThumbProximal"},
	{"side": "Left", "joint": 4, "parent": 3, "bone": "LeftThumbDistal"},
	{"side": "Left", "joint": 7, "parent": 1, "bone": "LeftIndexProximal"},
	{"side": "Left", "joint": 8, "parent": 7, "bone": "LeftIndexIntermediate"},
	{"side": "Left", "joint": 9, "parent": 8, "bone": "LeftIndexDistal"},
	{"side": "Left", "joint": 12, "parent": 1, "bone": "LeftMiddleProximal"},
	{"side": "Left", "joint": 13, "parent": 12, "bone": "LeftMiddleIntermediate"},
	{"side": "Left", "joint": 14, "parent": 13, "bone": "LeftMiddleDistal"},
	{"side": "Left", "joint": 17, "parent": 1, "bone": "LeftRingProximal"},
	{"side": "Left", "joint": 18, "parent": 17, "bone": "LeftRingIntermediate"},
	{"side": "Left", "joint": 19, "parent": 18, "bone": "LeftRingDistal"},
	{"side": "Left", "joint": 22, "parent": 1, "bone": "LeftLittleProximal"},
	{"side": "Left", "joint": 23, "parent": 22, "bone": "LeftLittleIntermediate"},
	{"side": "Left", "joint": 24, "parent": 23, "bone": "LeftLittleDistal"},
	{"side": "Right", "joint": 1, "parent": -1, "bone": "RightHand"},
	{"side": "Right", "joint": 2, "parent": 1, "bone": "RightThumbMetacarpal"},
	{"side": "Right", "joint": 3, "parent": 2, "bone": "RightThumbProximal"},
	{"side": "Right", "joint": 4, "parent": 3, "bone": "RightThumbDistal"},
	{"side": "Right", "joint": 7, "parent": 1, "bone": "RightIndexProximal"},
	{"side": "Right", "joint": 8, "parent": 7, "bone": "RightIndexIntermediate"},
	{"side": "Right", "joint": 9, "parent": 8, "bone": "RightIndexDistal"},
	{"side": "Right", "joint": 12, "parent": 1, "bone": "RightMiddleProximal"},
	{"side": "Right", "joint": 13, "parent": 12, "bone": "RightMiddleIntermediate"},
	{"side": "Right", "joint": 14, "parent": 13, "bone": "RightMiddleDistal"},
	{"side": "Right", "joint": 17, "parent": 1, "bone": "RightRingProximal"},
	{"side": "Right", "joint": 18, "parent": 17, "bone": "RightRingIntermediate"},
	{"side": "Right", "joint": 19, "parent": 18, "bone": "RightRingDistal"},
	{"side": "Right", "joint": 22, "parent": 1, "bone": "RightLittleProximal"},
	{"side": "Right", "joint": 23, "parent": 22, "bone": "RightLittleIntermediate"},
	{"side": "Right", "joint": 24, "parent": 23, "bone": "RightLittleDistal"},
]

var _recording := false
var _elapsed := 0.0
var _sample_accumulator := 0.0
var _animation: Animation
var _position_tracks: Dictionary = {}
var _rotation_tracks: Dictionary = {}
var _status_label: Label
var _time_label: Label
var _name_edit: LineEdit
var _save_dialog: FileDialog
var _headset_label: Label3D
var _pinch_latched := false


func _ready() -> void:
	_start_openxr()
	_build_interface()
	_build_headset_display()
	_new_animation()
	_update_status()


func _start_openxr() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		push_warning("OpenXR is not active. Run Meta Quest Link or use desktop mode without VR.")
		return

	# Initializing OpenXR does not automatically enable stereo rendering on this viewport.
	get_viewport().use_xr = true
	# OpenXR handles frame pacing; desktop VSync can cause flicker or stutter.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	if RenderingServer.get_rendering_device() != null:
		get_viewport().vrs_mode = Viewport.VRS_XR

	print("OpenXR initialized; XR rendering enabled on the main viewport.")


func _process(delta: float) -> void:
	_poll_vr_record_gesture()
	if not _recording:
		_update_status()
		return
	_elapsed += delta
	_sample_accumulator += delta
	while _sample_accumulator >= 1.0 / SAMPLE_RATE:
		_sample_accumulator -= 1.0 / SAMPLE_RATE
		_capture_frame(_elapsed - _sample_accumulator)
	_time_label.text = "REC  %0.2f s" % _elapsed
	if _headset_label != null:
		_headset_label.text = "HANDCAP\nRECORDING  %0.2f s\nPinch right thumb and index to stop" % _elapsed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_recording()
		elif event.keycode == KEY_S:
			_save_dialog.popup_centered_ratio(0.7)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _new_animation() -> void:
	_animation = Animation.new()
	_animation.resource_name = "HandTake"
	_animation.step = 1.0 / SAMPLE_RATE
	_position_tracks.clear()
	_rotation_tracks.clear()
	for mapping: Dictionary in HAND_BONES:
		var path := "Skeleton3D:%s" % mapping.bone
		var p_track := _animation.add_track(Animation.TYPE_POSITION_3D)
		_animation.track_set_path(p_track, NodePath(path))
		_animation.track_set_interpolation_type(p_track, Animation.INTERPOLATION_LINEAR)
		var r_track := _animation.add_track(Animation.TYPE_ROTATION_3D)
		_animation.track_set_path(r_track, NodePath(path))
		_animation.track_set_interpolation_type(r_track, Animation.INTERPOLATION_LINEAR)
		_position_tracks[mapping.bone] = p_track
		_rotation_tracks[mapping.bone] = r_track


func _capture_frame(time: float) -> void:
	var trackers := {
		"Left": XRServer.get_tracker(LEFT_TRACKER) as XRHandTracker,
		"Right": XRServer.get_tracker(RIGHT_TRACKER) as XRHandTracker,
	}
	for mapping: Dictionary in HAND_BONES:
		var tracker: XRHandTracker = trackers[mapping.side]
		if tracker == null or not tracker.has_tracking_data:
			continue
		var joint_transform := tracker.get_hand_joint_transform(mapping.joint)
		if mapping.parent >= 0:
			var parent_transform := tracker.get_hand_joint_transform(mapping.parent)
			joint_transform = parent_transform.affine_inverse() * joint_transform
		var bone: String = mapping.bone
		_animation.track_insert_key(_position_tracks[bone], time, joint_transform.origin)
		_animation.track_insert_key(_rotation_tracks[bone], time, joint_transform.basis.get_rotation_quaternion())
	_animation.length = maxf(_animation.length, time + 1.0 / SAMPLE_RATE)


func _poll_vr_record_gesture() -> void:
	var tracker := XRServer.get_tracker(RIGHT_TRACKER) as XRHandTracker
	if tracker == null or not tracker.has_tracking_data:
		_pinch_latched = false
		return
	var thumb_tip := tracker.get_hand_joint_transform(5).origin
	var index_tip := tracker.get_hand_joint_transform(10).origin
	var pinch_distance := thumb_tip.distance_to(index_tip)
	if pinch_distance < 0.025 and not _pinch_latched:
		_pinch_latched = true
		_toggle_recording()
	elif pinch_distance > 0.045:
		_pinch_latched = false


func _toggle_recording() -> void:
	if _recording:
		_recording = false
		if _elapsed > 0.0:
			_animation.length = _elapsed
			_animation.resource_name = _safe_animation_name()
			_status_label.text = "Recording stopped. Save the take to use it in an AnimationPlayer."
	else:
		_new_animation()
		_elapsed = 0.0
		_sample_accumulator = 0.0
		_recording = true
		_status_label.text = "Recording both hands. Press Space or Stop when finished."
	_update_buttons()


func _save_animation(path: String) -> void:
	if _recording:
		_toggle_recording()
	if _elapsed <= 0.0:
		_status_label.text = "Nothing recorded yet."
		return
	_animation.resource_name = _safe_animation_name()
	var error := ResourceSaver.save(_animation, path)
	if error == OK:
		_status_label.text = "Saved: %s" % path
	else:
		_status_label.text = "Save failed (error %d). Choose a writable .tres path." % error


func _safe_animation_name() -> String:
	var value := _name_edit.text.strip_edges()
	return value if not value.is_empty() else "HandTake"


func _update_status() -> void:
	var left := XRServer.get_tracker(LEFT_TRACKER) as XRHandTracker
	var right := XRServer.get_tracker(RIGHT_TRACKER) as XRHandTracker
	var left_state := _hand_tracker_state(left)
	var right_state := _hand_tracker_state(right)
	var xr_state := "OpenXR active" if XRServer.primary_interface != null and XRServer.primary_interface.is_initialized() else "OpenXR not active — start Meta Quest Link first"
	var tracker_note := "\nQuest Link on PC does not provide hand joints; run a native Quest app." if left == null or right == null else ""
	_status_label.text = "%s\nLeft hand: %s    Right hand: %s" % [xr_state, left_state, right_state]
	if left == null or right == null:
		_status_label.text += "\nNo hand tracker from runtime. Quest Link on PC does not expose optical hand joints; run a native Quest build."
	if _headset_label != null and not _recording:
		_headset_label.text = "HANDCAP\n%s\nL: %s    R: %s%s\nPinch right thumb and index to record" % [xr_state, left_state, right_state, tracker_note]
	_update_buttons()


func _hand_tracker_state(tracker: XRHandTracker) -> String:
	if tracker == null:
		return "unavailable"
	return "tracked" if tracker.has_tracking_data else "waiting for hand"


func _update_buttons() -> void:
	if has_node("UI/Panel/Margin/Rows/Record"):
		get_node("UI/Panel/Margin/Rows/Record").text = "Stop Recording" if _recording else "Record"


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.03
	panel.anchor_top = 0.04
	panel.anchor_right = 0.39
	panel.anchor_bottom = 0.38
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "HAND TAKE  /  OPENXR"
	title.add_theme_font_size_override("font_size", 22)
	rows.add_child(title)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_status_label)
	_time_label = Label.new()
	_time_label.text = "Ready  0.00 s"
	rows.add_child(_time_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Animation name"
	_name_edit.text = "HandTake"
	rows.add_child(_name_edit)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var record_button := Button.new()
	record_button.name = "Record"
	record_button.text = "Record"
	record_button.pressed.connect(_toggle_recording)
	buttons.add_child(record_button)
	var save_button := Button.new()
	save_button.text = "Save .tres"
	save_button.pressed.connect(func() -> void: _save_dialog.popup_centered_ratio(0.7))
	buttons.add_child(save_button)
	var hint := Label.new()
	hint.text = "Space: record/stop    S: save    Escape: quit"
	rows.add_child(hint)
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.tres", "Godot Animation Resource")
	_save_dialog.current_file = "HandTake.tres"
	_save_dialog.file_selected.connect(_save_animation)
	canvas.add_child(_save_dialog)


func _build_headset_display() -> void:
	_headset_label = Label3D.new()
	_headset_label.name = "HeadsetStatus"
	_headset_label.position = Vector3(0.0, -0.12, -1.4)
	_headset_label.font_size = 48
	_headset_label.pixel_size = 0.0015
	_headset_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_headset_label.no_depth_test = true
	_headset_label.modulate = Color(0.78, 1.0, 0.9)
	get_node("XROrigin3D/XRCamera3D").add_child(_headset_label)
