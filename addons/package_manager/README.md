# Package Manager (Godot 4.6 Editor Plugin)

Pack and unpack project files and folders into a local package store. Install packages into any Godot project. Supports thumbnails, photos, and videos per package with drag-drop and paste.

## Installation

1. Copy the `addons/package_manager` folder into your Godot project's `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable **Package Manager**.

## Usage

- **Open**: **Project → Tools → Package Manager** (or the menu entry you configured).
- **Add Package**: Create a new package from files/folders. Choose an ID, name, version, and add paths via "Add files..." or "Add folder...".
- **Install**: Select a package and click **Install** to copy its contents into the current project (`res://`).
- **Preview**: Open package details, packed paths, and manage **thumbnails & media** (images/videos). Add media by drag-drop, paste (file paths in clipboard), or "Add media...". Set as thumbnail or remove from the list.
- **Duplicate**: Copy a package under a new ID.
- **Remove**: Delete a package from the store (with confirmation).
- **Settings**: Set the **package store path** (default: `user://package_manager/packs`) and **Overwrite existing files when installing**.

## Making the plugin available in all projects (without rebuilding Godot)

Godot does not support “global” editor plugins. You can still use this addon across projects in these ways:

### 1. Per-project (standard)

Copy `addons/package_manager` into each project and enable the plugin. No engine changes.

### 2. Project template

Create a Godot project template that already includes the `addons/package_manager` folder. New projects created from that template will have the Package Manager by default.

### 3. Symlink / junction (one copy, many projects)

Install the addon once in a fixed folder, then point each project’s addon folder at it:

**Windows (junction):**

```bat
mklink /J "C:\Path\To\YourProject\addons\package_manager" "C:\Path\To\SharedAddons\package_manager"
```

**macOS / Linux (symlink):**

```bash
ln -s /path/to/shared_addons/package_manager /path/to/your_project/addons/package_manager
```

Then enable the plugin in each project. All projects use the same addon files.

### 4. Global-project frameworks

Use a framework like [godot-global-project](https://github.com/dugramen/godot-global-project) so a single “global” project holds editor plugins that run in every project. Follow that project’s setup instructions.

## Store layout

- **Default store path**: `user://package_manager/packs/` (per user, shared across projects on the same machine).
- Each package is a folder: `{store}/{package_id}/` with:
  - `manifest.cfg` — id, name, version, paths, thumbnail, media list.
  - `content/` — copied project files/folders.
  - `media/` — thumbnails and media (images: png, jpg, webp; videos: webm, ogv, mp4).

## License

Same as your project.
