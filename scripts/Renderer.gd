extends RefCounted
class_name Renderer

# Workshop train palette
const C_NIGHT := Color(0.04, 0.07, 0.09, 1.0)
const C_PETROL := Color(0.11, 0.22, 0.21, 1.0)
const C_PETROL_DARK := Color(0.06, 0.13, 0.14, 1.0)
const C_TILE := Color(0.77, 0.72, 0.53, 1.0)
const C_STEEL := Color(0.18, 0.22, 0.24, 1.0)
const C_STEEL_HI := Color(0.34, 0.39, 0.43, 1.0)
const C_BRASS := Color(0.80, 0.62, 0.24, 1.0)
const C_GLOW := Color(0.36, 0.89, 0.60, 1.0)
const C_WARM := Color(1.0, 0.95, 0.84, 1.0)
const C_RED := Color(0.90, 0.22, 0.27, 1.0)
const C_FOCUS_TINT := Color(0.56, 0.74, 0.86, 1.0)

var tex_tiles: Texture2D
var tex_player: Texture2D
var tex_enemies: Texture2D
var tex_props: Texture2D

func load_textures() -> void:
	if ResourceLoader.exists("res://assets/sprites/tiles_train.png"):
		tex_tiles = load("res://assets/sprites/tiles_train.png")
	if ResourceLoader.exists("res://assets/sprites/player_sheet.png"):
		tex_player = load("res://assets/sprites/player_sheet.png")
	if ResourceLoader.exists("res://assets/sprites/enemies_sheet.png"):
		tex_enemies = load("res://assets/sprites/enemies_sheet.png")
	if ResourceLoader.exists("res://assets/sprites/props_sheet.png"):
		tex_props = load("res://assets/sprites/props_sheet.png")

func draw_world(canvas: CanvasItem, sim: Simulation, viewport_size: Vector2, font: Font) -> void:
	# Consistent pixel scale centered in landscape viewport
	var scale_f: float = minf(viewport_size.x / 440.0, viewport_size.y / Simulation.ROOM_H)
	var offset := Vector2(
		(viewport_size.x - 440.0 * scale_f) * 0.5,
		(viewport_size.y - Simulation.ROOM_H * scale_f) * 0.5
	)

	# CCTV Replay uses a fixed wide security-camera angle of the entire wagon
	var cam_x: float = sim.camera_x
	var world_scale: float = scale_f
	if sim.mode == "REPLAY":
		world_scale = minf(viewport_size.x / Simulation.ROOM_W, viewport_size.y / Simulation.ROOM_H)
		offset = Vector2((viewport_size.x - Simulation.ROOM_W * world_scale) * 0.5, (viewport_size.y - Simulation.ROOM_H * world_scale) * 0.5)
		cam_x = 0.0

	var shake_off := Vector2.ZERO
	if sim.shake_frames > 0:
		shake_off = sim.shake_dir * (float(sim.shake_frames) * 0.55)

	canvas.draw_rect(Rect2(Vector2.ZERO, viewport_size), C_NIGHT)
	canvas.draw_set_transform(offset + shake_off, 0.0, Vector2(world_scale, world_scale))

	var bg_tint: Color = C_FOCUS_TINT if sim.focus_active else Color.WHITE

	# 1. Train interior & moving night station windows
	_draw_wagon_backdrop(canvas, sim, cam_x, bg_tint)

	# 2. Persistent slash/impact decals on floor/wall
	for d in sim.blood_decals:
		var p: Vector2 = d["pos"] - Vector2(cam_x, 0)
		var dir: Vector2 = d["dir"]
		canvas.draw_line(p + Vector2(0, -10), p + Vector2(0, -10) + dir * d["len"], C_RED * Color(0.75, 0.75, 0.75, 0.85), 2.5)
		canvas.draw_rect(Rect2(p.x - 6, Simulation.FLOOR_Y - 2, 14, 2), C_RED * Color(0.7, 0.7, 0.7, 0.9))

	# 3. Solid walls, counters, one-way shelves, exits
	_draw_geometry(canvas, sim, cam_x, bg_tint, font)

	# 4. Doors (frosted glass silhouette + brass handle)
	for d in sim.doors:
		var dx: float = d["x"] - cam_x
		if d["open"]:
			canvas.draw_rect(Rect2(dx + d["open_dir"] * 8.0, d["y"], 4.0, d["h"]), C_STEEL_HI * bg_tint)
		else:
			canvas.draw_rect(Rect2(dx, d["y"], d["w"], d["h"]), C_STEEL * bg_tint)
			canvas.draw_rect(Rect2(dx + 2, d["y"] + 4, d["w"] - 4, 16), Color(0.55, 0.68, 0.66, 0.72) * bg_tint)
			# Guard silhouette visible through frosted glass before opening
			for e in sim.enemies:
				if e["alive"] and absf(e["pos"].x - d["x"]) < 34.0:
					canvas.draw_rect(Rect2(dx + 3, d["y"] + 8, 4, 11), Color(0.08, 0.11, 0.12, 0.75))
			canvas.draw_rect(Rect2(dx + d["w"] - 3, d["y"] + 22, 3, 2), C_BRASS)

	# 5. Hazards (cameras, cable power light, turret, barrels, smoke)
	_draw_hazards(canvas, sim, cam_x, bg_tint)

	# 6. Portable items (warm white highlight for interactive clarity)
	for it in sim.items:
		if it["active"]:
			var ip: Vector2 = it["pos"] - Vector2(cam_x, 0)
			canvas.draw_rect(Rect2(ip.x - 4, ip.y - 8, 8, 8), Color(1.0, 0.95, 0.84, 0.25))
			if tex_props:
				var src_x: float = 0.0 if it["type"] == "bottle" else (16.0 if it["type"] == "knife" else 32.0)
				canvas.draw_texture_rect_region(tex_props, Rect2(ip.x - 8, ip.y - 16, 16, 16), Rect2(src_x, 0, 16, 32))

	# 7. Enemies & clear visual attack telegraphs (always readable even in focus/mute)
	_draw_enemies(canvas, sim, cam_x, font)

	# 8. Player silhouette (worker cape, swaying shoulder lamp, brass wrench)
	_draw_player(canvas, sim, cam_x)

	# 9. Slash arc & 3 distinct combat outcome visuals
	_draw_slash_and_sparks(canvas, sim, cam_x)

	# 10. Bullets (sharp warm core + brake-red trail, distinct from background reflections)
	for b in sim.bullets:
		if b["active"]:
			var bp: Vector2 = b["pos"] - Vector2(cam_x, 0)
			var tail: Vector2 = bp - b["vel"].normalized() * 11.0
			var col: Color = C_GLOW if b["owner"] == "player" else C_RED
			canvas.draw_line(tail, bp, col, 2.0)
			canvas.draw_rect(Rect2(bp.x - 1.5, bp.y - 1.5, 3, 3), C_WARM)

	# Reset transform for crisp screen-space HUD / Title / CCTV frame
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if sim.mode == "TITLE":
		_draw_title_overlay(canvas, viewport_size, font)
	elif sim.mode == "REPLAY":
		_draw_cctv_overlay(canvas, sim, viewport_size, font)

func _draw_wagon_backdrop(canvas: CanvasItem, sim: Simulation, cam_x: float, tint: Color) -> void:
	# Petrol green workshop panels & yellowed tile wainscoting
	canvas.draw_rect(Rect2(0, 24, 440, 118), C_PETROL * tint)
	canvas.draw_rect(Rect2(0, 142, 440, 62), C_TILE * Color(0.68, 0.68, 0.68, 1.0) * tint)
	canvas.draw_line(Vector2(0, 142), Vector2(440, 142), C_BRASS * tint, 2.0)

	# Passing night train windows (continuous from title screen into Wagon 1)
	var win_positions := [48.0, 188.0, 328.0, 448.0]
	for wx_world in win_positions:
		var wx: float = wx_world - cam_x
		if wx < -80.0 or wx > 460.0:
			continue
		canvas.draw_rect(Rect2(wx, 44, 68, 44), C_NIGHT)
		canvas.draw_rect(Rect2(wx, 44, 68, 44), C_STEEL_HI * tint, false, 2.0)
		# Scrolling station lamps outside window
		var lamp_x: float = wx + fmod(68.0 - fmod(float(sim.sim_tick) * 5.2 + wx_world, 84.0), 84.0) - 8.0
		if lamp_x >= wx + 2.0 and lamp_x <= wx + 56.0:
			canvas.draw_rect(Rect2(lamp_x, 58, 10, 3), C_WARM)
			canvas.draw_rect(Rect2(lamp_x - 3, 61, 16, 2), Color(1.0, 0.9, 0.65, 0.35))
		# Late extra lamp passing after previous lights cleared (Wagon 1 first-minute beat)
		if sim.wagon_id == 1 and sim.intro_extra_lamp_x > -20.0:
			var ex: float = sim.intro_extra_lamp_x - cam_x
			if ex >= wx and ex <= wx + 60.0:
				canvas.draw_rect(Rect2(ex, 56, 12, 4), C_WARM)

	# Distinct room silhouettes per wagon
	match sim.wagon_id:
		2: # Dining car hanging pans
			for px in [95.0, 155.0, 215.0, 295.0]:
				var sx: float = px - cam_x
				canvas.draw_line(Vector2(sx, 24), Vector2(sx, 46), C_STEEL_HI * tint, 1.5)
				canvas.draw_circle(Vector2(sx, 50), 6.0, C_PETROL_DARK * tint)
		3: # Mail car hanging mailbags & wire mesh
			for mx in [120.0, 235.0, 355.0]:
				var sx: float = mx - cam_x
				canvas.draw_rect(Rect2(sx - 12, 52, 24, 28), C_PETROL_DARK * tint, false, 1.0)
				canvas.draw_rect(Rect2(sx - 6, 86, 12, 16), C_BRASS * Color(0.6, 0.6, 0.6, 0.7) * tint)
		4: # Battery car ceramic insulators & cable conduits
			for ix in [80.0, 180.0, 280.0, 390.0]:
				var sx: float = ix - cam_x
				canvas.draw_rect(Rect2(sx - 3, 24, 6, 18), C_WARM * Color(0.75, 0.75, 0.75, 1.0) * tint)
				canvas.draw_line(Vector2(sx, 42), Vector2(sx + 90, 42), C_STEEL_HI * tint, 2.0)

func _draw_geometry(canvas: CanvasItem, sim: Simulation, cam_x: float, tint: Color, font: Font) -> void:
	# Floor & ceiling
	canvas.draw_rect(Rect2(0, 0, 440, 24), C_PETROL_DARK * tint)
	canvas.draw_rect(Rect2(0, Simulation.FLOOR_Y, 440, 36), C_STEEL * tint)
	canvas.draw_line(Vector2(0, Simulation.FLOOR_Y), Vector2(440, Simulation.FLOOR_Y), C_STEEL_HI * tint, 2.0)

	# Interior cover walls / counters
	for w in sim.walls:
		if w.position.y > 24.0 and w.position.y < Simulation.FLOOR_Y:
			var r := Rect2(w.position.x - cam_x, w.position.y, w.size.x, w.size.y)
			canvas.draw_rect(r, C_STEEL * tint)
			canvas.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3), C_BRASS * tint)

	# One-way shelves / platforms
	for p in sim.one_way_platforms:
		var r := Rect2(p.position.x - cam_x, p.position.y, p.size.x, p.size.y)
		canvas.draw_rect(r, C_STEEL_HI * tint)
		canvas.draw_line(r.position, Vector2(r.end.x, r.position.y), C_WARM * Color(0.8, 0.8, 0.8, 1.0) * tint, 1.5)

	# Glow-in-the-dark maintenance exit sign
	var ex := Rect2(sim.exit_zone.position.x - cam_x, sim.exit_zone.position.y, sim.exit_zone.size.x, sim.exit_zone.size.y)
	canvas.draw_rect(ex, C_PETROL_DARK)
	canvas.draw_rect(ex, C_GLOW, false, 1.5)
	canvas.draw_rect(Rect2(ex.position.x + 5, ex.position.y - 10, 18, 6), C_GLOW)

	# Wagon 3 upper staff hatch when Idil's radio tip was heard
	if sim.wagon_id == 3 and GameState.radio_listened:
		var ax := Rect2(sim.alt_exit_zone.position.x - cam_x, sim.alt_exit_zone.position.y, sim.alt_exit_zone.size.x, sim.alt_exit_zone.size.y)
		canvas.draw_rect(ax, Color(0.12, 0.28, 0.22, 0.9))
		canvas.draw_rect(ax, C_GLOW, false, 2.0)
		if font:
			canvas.draw_string(font, ax.position + Vector2(2, -4), "PERSONEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_GLOW)

	# Interactive hint plaque in world
	if sim.interact_sign.has("x") and font:
		var sx: float = sim.interact_sign["x"] - cam_x
		var sy: float = sim.interact_sign["y"]
		if absf(sim.player["pos"].x - sim.interact_sign["x"]) < 85.0:
			canvas.draw_string(font, Vector2(sx - 40, sy), sim.interact_sign["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_WARM)

func _draw_hazards(canvas: CanvasItem, sim: Simulation, cam_x: float, tint: Color) -> void:
	for cam in sim.cameras:
		var cp: Vector2 = cam["pos"] - Vector2(cam_x, 0)
		var cone_col: Color = Color(0.90, 0.22, 0.27, 0.24) if cam["alert"] > 0 else Color(0.36, 0.89, 0.60, 0.14)
		var pts := PackedVector2Array([cp, cp + Vector2(cam["dir"] * 85.0 - 24.0, 96.0), cp + Vector2(cam["dir"] * 85.0 + 24.0, 96.0)])
		canvas.draw_colored_polygon(pts, cone_col)
		canvas.draw_rect(Rect2(cp.x - 5, cp.y - 3, 10, 6), C_STEEL_HI)
		canvas.draw_rect(Rect2(cp.x + cam["dir"] * 4, cp.y - 1, 3, 3), C_RED if cam["alert"] > 0 else C_GLOW)

		# Live cable pulse feeding turret when camera triggers alarm
		if sim.turret.has("pos"):
			var tp: Vector2 = sim.turret["pos"] - Vector2(cam_x, 0)
			canvas.draw_line(cp, tp, C_STEEL_HI * tint, 2.0)
			if cam["alert"] > 0 or sim.turret.get("powered", false):
				var pulse_x: float = lerpf(cp.x, tp.x, fmod(sim.world_time * 2.5, 1.0))
				canvas.draw_circle(Vector2(pulse_x, cp.y), 3.0, C_RED)

	if sim.power_panel.has("pos"):
		var pp: Vector2 = sim.power_panel["pos"] - Vector2(cam_x, 0)
		canvas.draw_rect(Rect2(pp.x, pp.y, 16, 22), C_STEEL)
		canvas.draw_rect(Rect2(pp.x + 3, pp.y + 4, 10, 6), C_GLOW if sim.power_panel["active"] else C_RED)

	if sim.turret.has("pos") and sim.turret["alive"]:
		var tp: Vector2 = sim.turret["pos"] - Vector2(cam_x, 0)
		canvas.draw_rect(Rect2(tp.x - 8, tp.y - 5, 16, 10), C_STEEL_HI)
		canvas.draw_circle(tp, 3.0, C_RED if sim.turret["powered"] else C_GLOW)

	for b in sim.barrels:
		if b["intact"]:
			var bp: Vector2 = b["pos"] - Vector2(cam_x, 0)
			canvas.draw_rect(Rect2(bp.x - 6, bp.y - 9, 12, 18), C_RED * tint)
			canvas.draw_rect(Rect2(bp.x - 6, bp.y - 3, 12, 3), C_WARM)

	for s in sim.smokes:
		if s["timer"] > 0:
			var sp: Vector2 = s["pos"] - Vector2(cam_x, 0)
			var ratio: float = float(s["timer"]) / float(s["max_timer"])
			canvas.draw_circle(sp, s["radius"] * (0.7 + 0.3 * ratio), Color(0.76, 0.82, 0.80, 0.58 * ratio))

func _draw_enemies(canvas: CanvasItem, sim: Simulation, cam_x: float, font: Font) -> void:
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var ep: Vector2 = e["pos"] - Vector2(cam_x, 0)
		var col_idx: int = 0
		match e["type"]:
			"pistol": col_idx = 1
			"shotgun": col_idx = 2
			"shield": col_idx = 3
			"boss": col_idx = 4

		if tex_enemies:
			var dst := Rect2(ep.x - 16, ep.y - 32, 32, 32)
			if e["facing"] < 0:
				dst.position.x += 32
				dst.size.x = -32
			canvas.draw_texture_rect_region(tex_enemies, dst, Rect2(col_idx * 32, 0, 32, 32))

		# Stun stars / rear backstab indicator
		if e["stun"] > 0 and font:
			canvas.draw_string(font, ep + Vector2(-8, -32), "SERSEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_WARM)
		elif e["turn_window"] > 0 and font:
			canvas.draw_string(font, ep + Vector2(-8, -32), "ARKA ACIK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_GLOW)

		# Clear attack telegraphs (brake-red line/cone/glint readable with zero audio)
		if e["windup"] > 0:
			var muzzle := ep + Vector2(e["facing"] * 8, -14)
			if e["type"] == "pistol":
				canvas.draw_line(muzzle, muzzle + e["aim_dir"] * 220.0, C_RED, 1.5)
			elif e["type"] == "shotgun":
				var p1: Vector2 = muzzle + e["aim_dir"].rotated(-0.18) * 145.0
				var p2: Vector2 = muzzle + e["aim_dir"].rotated(0.18) * 145.0
				canvas.draw_colored_polygon(PackedVector2Array([muzzle, p1, p2]), Color(0.90, 0.22, 0.27, 0.28))
			elif e["type"] == "melee" or e["type"] == "shield":
				canvas.draw_circle(ep + Vector2(-e["facing"] * 6, -16), 4.0, C_RED)
			elif e["type"] == "boss":
				if sim.boss_signal == "YELLOW":
					var tp: Vector2 = sim.boss_telegraph_pos - Vector2(cam_x, 0)
					canvas.draw_rect(Rect2(tp.x - 7, tp.y - 26, 14, 26), Color(1.0, 0.85, 0.25, 0.45), false, 2.0)
				else:
					canvas.draw_line(muzzle, muzzle + Vector2(e["facing"] * 180.0, 0), C_RED, 2.0)

		# Wagon 1 door opening weapon glint on second guard
		if sim.wagon_id == 1 and e["id"] == 2 and sim.door1_glint_timer > 0:
			canvas.draw_circle(ep + Vector2(-7, -14), 5.0, C_WARM)

func _draw_player(canvas: CanvasItem, sim: Simulation, cam_x: float) -> void:
	if not sim.player["alive"]:
		return
	var pp: Vector2 = sim.player["pos"] - Vector2(cam_x, 0)
	var f_idx: int = 0
	match sim.player["anim"]:
		"run": f_idx = sim.player["anim_frame"]
		"roll": f_idx = 3
		"wall": f_idx = 4
		"slash": f_idx = 5

	if tex_player:
		var dst := Rect2(pp.x - 16, pp.y - 32, 32, 32)
		if sim.player["facing"] < 0:
			dst.position.x += 32
			dst.size.x = -32
		canvas.draw_texture_rect_region(tex_player, dst, Rect2(f_idx * 32, 0, 32, 32))

	# Inertial shoulder lamp glow (sways 1 frame forward on sudden stop)
	var lamp_pos := pp + Vector2(sim.player["facing"] * 5.0 + sim.player["lamp_sway"], -18.0)
	canvas.draw_circle(lamp_pos, 2.2, C_WARM)
	canvas.draw_circle(lamp_pos, 6.0, Color(1.0, 0.95, 0.84, 0.18))

func _draw_slash_and_sparks(canvas: CanvasItem, sim: Simulation, cam_x: float) -> void:
	if sim.slash_fx.get("timer", 0) > 0:
		var orig: Vector2 = sim.slash_fx["origin"] - Vector2(cam_x, 0)
		var dir: Vector2 = sim.slash_fx["dir"]
		var tip: Vector2 = orig + dir * 32.0
		var perp := Vector2(-dir.y, dir.x) * 10.0
		var outcome: String = sim.slash_fx.get("outcome", "whiff")

		if outcome == "whiff":
			# Subtle cloth & air arc (no bright explosion on whiff)
			canvas.draw_line(orig + perp * 0.4, tip, Color(0.78, 0.86, 0.86, 0.55), 2.0)
			canvas.draw_line(orig - perp * 0.4, tip, Color(0.55, 0.65, 0.68, 0.35), 1.5)
		elif outcome == "block":
			# Heavy dull shield knockback ring
			canvas.draw_arc(tip, 9.0, 0.0, TAU, 16, C_STEEL_HI, 2.5)
		else:
			# Crisp directional crimson/warm blade arc on real hit or deflection
			var pts := PackedVector2Array([orig, tip - perp, orig + dir * 36.0, tip + perp])
			canvas.draw_colored_polygon(pts, C_WARM if outcome == "deflect" else C_RED)

	for sp in sim.clash_sparks:
		var p: Vector2 = sp["pos"] - Vector2(cam_x, 0)
		var col: Color = C_BRASS if sp["kind"] == "clash" else (C_WARM if sp["kind"] == "deflect" else C_RED)
		for a in range(6):
			var v := Vector2.RIGHT.rotated(float(a) * TAU / 6.0) * 10.0
			canvas.draw_line(p, p + v, col, 1.5)

func _draw_title_overlay(canvas: CanvasItem, vp: Vector2, font: Font) -> void:
	# Condensation mist over the train window, seamlessly revealing Wagon 1 on start
	canvas.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.05, 0.09, 0.10, 0.48))
	if font:
		canvas.draw_string(font, Vector2(vp.x * 0.5 - 110, vp.y * 0.36), "SON HAT", HORIZONTAL_ALIGNMENT_CENTER, 220, 44, C_WARM)
		canvas.draw_string(font, Vector2(vp.x * 0.5 - 170, vp.y * 0.45), "GECE TRENI  //  VAGON 01-05", HORIZONTAL_ALIGNMENT_CENTER, 340, 16, C_GLOW)
		canvas.draw_string(font, Vector2(vp.x * 0.5 - 170, vp.y * 0.62), "BASLAMAK ICIN DOKUN", HORIZONTAL_ALIGNMENT_CENTER, 340, 20, C_WARM)

func _draw_cctv_overlay(canvas: CanvasItem, sim: Simulation, vp: Vector2, font: Font) -> void:
	# Fixed train security camera frame, blinking REC light, and line number
	canvas.draw_rect(Rect2(16, 16, vp.x - 32, vp.y - 32), C_GLOW, false, 2.0)
	if (sim.sim_tick / 15) % 2 == 0:
		canvas.draw_circle(Vector2(42, 42), 7.0, C_RED)
	if font:
		canvas.draw_string(font, Vector2(58, 48), "KAYIT  //  HAT-0%d  [1.0x GERCEK HIZ]" % sim.wagon_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_WARM)
		var pct: int = int(100.0 * float(sim.replay_idx) / maxf(1.0, float(sim.recording.size() - 1)))
		canvas.draw_string(font, Vector2(vp.x - 190, 48), "KARE %d%%" % pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_GLOW)
