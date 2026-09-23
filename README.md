# Handcap

Handcap records Quest hand tracking through Godot's OpenXR hand trackers and saves the result as a native Godot `Animation` resource (`.tres`). It creates position and quaternion rotation tracks for both hands using the standard `SkeletonProfileHumanoid` hand bone names.

## Run in VR through Meta Quest Link

1. Start Meta Quest Link and make sure the headset is connected and visible to the OpenXR runtime.
2. Open this project in Godot 4.8. OpenXR and its hand tracking extension are enabled in `project.godot`; the project uses the Vulkan renderer for OpenXR.
3. Run the project. The startup script enables XR rendering on the main viewport and disables desktop VSync. Accept the OpenXR startup prompt if shown, and allow hand tracking in the headset. Use the desktop window for recording controls.
4. Pinch the right thumb and index finger together to start recording. Pinch again to stop. You can also press **Space** or use the desktop panel.
5. Click **Save .tres** (or press **S**), choose a writable folder in the project, and save the take. Godot will import the resource; it can then be assigned to an `AnimationPlayer` library.

Quest Link can render the Windows app in the headset, but Godot's current hand-tracking documentation says Meta Link does not expose optical hand joints to the app. In Link mode this project can therefore show `OpenXR active` while both hands remain untracked. To record hands without controllers, export and run the app natively on the Quest; the headset's hand tracking then feeds Godot's OpenXR hand trackers.

## Run as a standalone Quest app

Quest Link runs the Windows build through the PC OpenXR runtime. To install and launch the app directly on the headset, configure an Android export preset with Gradle and OpenXR, then deploy the exported APK. Enable the Meta Quest XR feature and hand tracking in that preset. Godot 4.6 and later can export to Android directly; the Godot OpenXR Vendors plugin is optional but recommended and adds Meta-specific settings. The native Meta OpenXR SDK is not needed for this project's standard OpenXR hand tracking path.

## Use the animation

Each recorded track is addressed as `Skeleton3D:<HumanoidBoneName>`. The target scene should have a node named `Skeleton3D` at the same relative path and a humanoid skeleton with matching bone names. Add the saved animation to an `AnimationPlayer` whose root can resolve that path. Tracks contain local position and rotation samples at 30 Hz; the hand-root (`LeftHand` / `RightHand`) positions are relative to the OpenXR hand tracking space, while the finger joints are relative to their mapped parent joint.

The export follows Godot's 54-bone humanoid profile. It records wrist/hand, thumb metacarpal/proximal/distal, and the proximal/intermediate/distal joints for index, middle, ring, and little fingers. OpenXR fingertip joints and finger metacarpals that do not have a corresponding humanoid bone are intentionally omitted.

**Coordinate-space note:** HumanoidProfile standardizes names, not a universal rig's bone rest axes. For a particular avatar, verify the recorded hand local axes against that skeleton; rigs with different rest orientations may need retargeting or a rest-pose correction before playback.
