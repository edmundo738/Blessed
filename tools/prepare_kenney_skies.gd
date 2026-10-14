extends SceneTree
## Rebuild the in-game CC0 sky panoramas at 2K with a high-quality filter.
## The downloaded 4K masters remain in the task's work/download folder.

const SKY_FILES := [
	"res://content/fx/kenney/sky/skybox-day.png",
	"res://content/fx/kenney/sky/skybox-morning.png",
	"res://content/fx/kenney/sky/skybox-night.png",
]


func _initialize() -> void:
	for path in SKY_FILES:
		var absolute_path := ProjectSettings.globalize_path(path)
		var image := Image.load_from_file(absolute_path)
		if image == null or image.is_empty():
			push_error("Could not open panorama: %s" % path)
			quit(1)
			return
		var source_size := image.get_size()
		image.resize(2048, 1024, Image.INTERPOLATE_LANCZOS)
		var error := image.save_png(absolute_path)
		if error != OK:
			push_error("Could not save panorama: %s" % path)
			quit(1)
			return
		print("SKY_OPTIMIZED %s: %s -> %s" % [path, source_size, image.get_size()])
	quit(0)
