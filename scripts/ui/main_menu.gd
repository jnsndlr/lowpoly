extends Control
## Title screen: Play (the main map), Sandbox (the procedural test map) or Quit.
##
## Debug args after `--` skip the menu so the existing command-line workflow keeps
## working: `--main` opens the main map, any other arg (e.g. --seed=123) the sandbox.

const BG := Color(0.05, 0.09, 0.11)
const TEXT := Color(0.9, 0.94, 0.95)
const MUTED := Color(0.58, 0.66, 0.68)
const ACCENT := Color(0.47, 0.86, 0.6)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		Scenes.go.call_deferred(get_tree(), Scenes.MAIN_MAP if "--main" in args else Scenes.SANDBOX)
		return
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var bold := SystemFont.new()
	bold.font_weight = 700
	var title := Label.new()
	title.text = "TIDEWAYS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TEXT)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Run the ferries that keep the islands moving."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", MUTED)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 28
	col.add_child(gap)

	var play := _button(col, "Play", func(): Scenes.go(get_tree(), Scenes.MAIN_MAP))
	_button(col, "Sandbox", func(): Scenes.go(get_tree(), Scenes.SANDBOX))
	_button(col, "Quit", func(): get_tree().quit())
	play.grab_focus()


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
