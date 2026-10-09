extends SceneTree
## Renders the Blender-built vehicles as a reference-style sheet: each variant from the
## front three-quarters (long lens), two to a row, in one PNG.
##   godot --path . --script tools/vehicle_sheet.gd -- --out=FILE.png [--only=suv_] [--rear]
##     [--yaw=DEG] [--pitch=DEG] [--view=M] [--look=X,Y,Z] [--cell=WxH]  (pass --resolution to match the cell)

var out := "user://vehicle_sheet.png"
var only := "suv_"
var yaw := 52.0
var pitch := 18.0
var cell := Vector2i(720, 440)
var view := 4.4             # metres the frame spans vertically
var look := Vector3.ZERO    # shift of the framing centre (m)
var paints := {
	"suv_crossover": 1, "suv_threerow": 7, "suv_luxury": 4, "suv_coupe": 12, "suv_ev": 3,
	"suv_cherokee": 5, "suv_offroad": 9, "suv_nineties": 11,
	"sedan_modern": 1, "sedan_sport": 5, "sedan_boxy": 7, "sedan_nineties": 9,
	"sedan_luxury": 10, "sedan_ev": 12, "sedan_compact": 11, "sedan_exec": 2,
	"minivan_family": 10, "minivan_nineties": 11, "minivan_modern": 4, "minivan_bold": 8,
	"minivan_compact": 5, "minivan_ev": 0, "minivan_boxy": 9, "minivan_suvish": 13,
	"van_cargo": 0, "van_passenger": 5, "van_hightop": 12, "van_retro": 10,
	"van_camper": 9, "van_shuttle": 3, "van_compact": 7, "van_overland": 9,
}
var cam: Camera3D
var holder: Node3D
var names: Array = []
var sheet: Image
var idx := 0
var frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a == "--rear":
			yaw += 180.0
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a.begins_with("--view="):
			view = float(a.substr(7))
		elif a.begins_with("--look="):
			var xyz := a.substr(7).split(",")
			look = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
		elif a.begins_with("--cell="):
			var wh := a.substr(7).split("x")
			cell = Vector2i(int(wh[0]), int(wh[1]))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.96, 0.95, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.5, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.96, 0.95, 0.92)
	ground.material_override = gm
	root.add_child(ground)
	holder = Node3D.new()
	root.add_child(holder)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	for n: String in VehicleData.VARIANTS:
		if n.begins_with(only) or only == "":
			names.append(n)
	var rows := int(ceil(names.size() / 2.0))
	sheet = Image.create(cell.x * 2, cell.y * rows, false, Image.FORMAT_RGBA8)


func _process(_delta: float) -> bool:
	frames += 1
	if frames % 4 == 1:
		if idx >= names.size():
			sheet.save_png(out)
			print("sheet: ", out, " (", names.size(), " vehicles)")
			return true
		var n: String = names[idx]
		for c in holder.get_children():
			c.queue_free()
		var mi := MeshInstance3D.new()
		mi.mesh = Models.vehicle(n, paints.get(n, 0))
		mi.material_override = Models.vc_material()
		holder.add_child(mi)
		var size: Vector3 = VehicleData.VARIANTS[n]["size"]
		var target := Vector3(0, size.y * 0.45, 0) + look
		var y := deg_to_rad(yaw)
		var p := deg_to_rad(pitch)
		cam.position = target + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * 20.0
		cam.look_at(target)
		# Same scale for every vehicle, so sizes compare across the sheet.
		cam.size = view
	elif frames % 4 == 0:
		var img := root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != cell:
			img.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((idx % 2) * cell.x, (idx / 2) * cell.y))
		idx += 1
	return false
