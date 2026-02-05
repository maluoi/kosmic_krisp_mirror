# KosmicKrisp macOS Vulkan Driver

**Current Version:** 1.4.341.0

Pre-built `libvulkan_kosmickrisp.dylib` automatically extracted from the [LunarG Vulkan SDK](https://vulkan.lunarg.com/).

## Usage

See the [Releases](../../releases) page for pre-built binaries. You should not need to clone this repository.

Each release includes:
- `libvulkan_kosmickrisp.dylib` - The Vulkan driver
- `libkosmickrisp_icd.json` - ICD manifest for the Vulkan loader
- `LICENSE.txt` - License terms

### Cmake

If you use cmake, you can integrate this into your project something like this:

```cmake
if (APPLE)
	message(STATUS "Fetching KosmicKrisp...")
	FetchContent_Declare(kosmickrisp
		URL https://github.com/maluoi/kosmic_krisp_mirror/releases/download/1.4.341.0/kosmickrisp.zip
		DOWNLOAD_EXTRACT_TIMESTAMP TRUE )
	FetchContent_MakeAvailable(kosmickrisp)

	add_library          (kosmickrisp SHARED IMPORTED GLOBAL)
	set_target_properties(kosmickrisp PROPERTIES
		IMPORTED_LOCATION "${kosmickrisp_SOURCE_DIR}/libvulkan_kosmickrisp.dylib" )
	message(STATUS "KosmicKrisp: ${kosmickrisp_SOURCE_DIR}/libvulkan_kosmickrisp.dylib")

	target_link_libraries(your_project PRIVATE kosmickrisp)
endif()
```

## License

The KosmicKrisp driver has its own license, see `LICENSE.txt` in the release zip.

This repository automation is provided as-is for convenience.