extends Node2D

var sim: Simulation
var renderer: Renderer
var audio: Node
var font: Font

# Multi-touch tracking for Infinix GT 20 Pro landscape play
var active_touches: Dictionary = {} # finger_id -> {pos, action}
var touch_buttons: Array[Dictionary] = []
var replay_buttons: Array[Dictionary] = []
var dialogue_buttons: Array[Dictionary] = []

# Radio dialogue state
var radio_text_progress: float = 0.0
var radio_prompt_active: bool = false
var radio_choice_made: bool = false

func _ready() -> void:
	var audio_script = load("res://scripts/AudioEngine.gd")
	audio = audio_script.new()
	add_child(audio)

	renderer = Renderer.new()
	renderer.load_textures()
	font = ThemeDB.fallback_font

	sim = Simulation.new()
	sim.init_wagon(GameState.current_wagon)

	# Allow headless automated verification via `-- --verify`
	if "--verify" in OS.get_cmdline_user_args() or "--verify" in OS.get_cmdline_args():
		_run_headless_verification()
		get_tree().quit(0)
		return

	_layout_touch_controls()
	get_viewport().size_changed.connect(_layout_touch_controls)

func _notification(what: int) -> void:
	# Reset held inputs when app goes to background or loses focus
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_all_inputs()

func _clear_all_inputs() -> void:
	if sim == null:
		return
	active_touches.clear()
	sim.input_dir = 0.0
	sim.input_down = false
	sim.input_focus = false
	sim.jump_held = false
	sim.slash_held = false
	sim.clear_buffered_commands()

func _layout_touch_controls() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1280, 720)

	# Respect Android display cutout / safe area (Infinix GT 20 Pro punch-hole & edges)
	var safe := DisplayServer.get_display_safe_area()
	var pad_l: float = maxf(24.0, float(safe.position.x) + 12.0)
	var pad_r: float = maxf(24.0, vp.x - float(safe.end.x) + 12.0)
	var pad_b: float = 24.0

	# Left thumb: movement + Focus; Right thumb: Slash (single tap), Roll, Jump, Use
	touch_buttons = [
		{"id": "left",  "label": "<",      "rect": Rect2(pad_l, vp.y - pad_b - 92, 86, 86)},
		{"id": "right", "label": ">",      "rect": Rect2(pad_l + 98, vp.y - pad_b - 92, 86, 86)},
		{"id": "down",  "label": "v",      "rect": Rect2(pad_l + 49, vp.y - pad_b - 186, 86, 78)},
		{"id": "focus", "label": "ODAK",   "rect": Rect2(pad_l + 196, vp.y - pad_b - 84, 92, 78)},

		{"id": "slash", "label": "KES",    "rect": Rect2(vp.x - pad_r - 104, vp.y - pad_b - 104, 104, 104)},
		{"id": "roll",  "label": "TAKLA",  "rect": Rect2(vp.x - pad_r - 214, vp.y - pad_b - 92, 96, 86)},
		{"id": "jump",  "label": "ZIPLA",  "rect": Rect2(vp.x - pad_r - 104, vp.y - pad_b - 208, 96, 88)},
		{"id": "use",   "label": "KULLAN", "rect": Rect2(vp.x - pad_r - 214, vp.y - pad_b - 196, 96, 82)},
		{"id": "mute",  "label": "SES",    "rect": Rect2(vp.x - pad_r - 78, 18, 68, 42)},
	]

	# Replay controls (visible only during CCTV replay, plus 1-tap skip)
	var cy: float = vp.y - 76.0
	replay_buttons = [
		{"id": "rw_back",  "label": "<< GERI",   "rect": Rect2(vp.x * 0.5 - 270, cy, 110, 52)},
		{"id": "rw_pause", "label": "DUR/DEVAM", "rect": Rect2(vp.x * 0.5 - 148, cy, 136, 52)},
		{"id": "rw_fwd",   "label": "ILERI >>",  "rect": Rect2(vp.x * 0.5 + 0,   cy, 110, 52)},
		{"id": "rw_skip",  "label": "GEC >",     "rect": Rect2(vp.x * 0.5 + 124, cy, 146, 52)},
	]

	dialogue_buttons = [
		{"id": "wait", "label": "DINLE (BEKLE)",     "rect": Rect2(vp.x * 0.5 - 250, 126, 230, 44)},
		{"id": "cut",  "label": "SOZUNU KES (YURU)", "rect": Rect2(vp.x * 0.5 + 20,  126, 230, 44)},
	]

func _physics_process(_delta: float) -> void:
	_poll_keyboard_fallback()
	sim.step_fixed()

	for ev in sim.frame_events:
		if ev["type"] == "sfx":
			audio.play_sfx(ev["name"], ev.get("pan", 0.0), ev.get("pitch", 1.0))

	if GameState.radio_started and not GameState.radio_finished:
		radio_prompt_active = true
		radio_text_progress = minf(1.0, radio_text_progress + 0.025)

	# Wagon 3 sealed shift manifest check if player cut Idil off earlier
	if sim.wagon_id == 3 and not GameState.radio_listened and not GameState.found_shift_manifest:
		if absf(sim.player["pos"].x - 245.0) < 28.0 and absf(sim.player["pos"].y - 128.0) < 22.0:
			GameState.found_shift_manifest = true
			audio.play_sfx("pickup", 0.0)

func _process(delta: float) -> void:
	var armed_vis := false
	for e in sim.enemies:
		if e["alive"] and e["type"] in ["pistol", "shotgun", "boss"]:
			armed_vis = true
			break
	audio.update_mix(
		sim.wagon_id,
		armed_vis,
		sim.focus_active,
		sim.mode == "REPLAY",
		sim.mode == "DEAD_REWIND",
		GameState.muted,
		delta
	)
	queue_redraw()

func _poll_keyboard_fallback() -> void:
	if active_touches.size() > 0:
		return
	var k_dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		k_dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		k_dir += 1.0
	sim.input_dir = k_dir
	sim.input_down = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	sim.input_focus = Input.is_key_pressed(KEY_SHIFT)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_pointer_down(event.index, event.position)
		else:
			_on_pointer_up(event.index)
	elif event is InputEventScreenDrag:
		_on_pointer_drag(event.index, event.position)
	elif event is InputEventMouseButton:
		if event.pressed:
			_on_pointer_down(-1, event.position)
		else:
			_on_pointer_up(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if sim.mode == "TITLE":
			sim.start_game_from_title()
			return
		match event.keycode:
			KEY_W, KEY_UP, KEY_SPACE:
				sim.jump_held = true
				sim.jump_buffer = Simulation.JUMP_BUFFER_FRAMES
			KEY_J, KEY_Z:
				sim.queue_slash(Vector2(sim.player["facing"], 0))
			KEY_K, KEY_X:
				sim.roll_pressed = true
			KEY_E, KEY_C:
				sim.use_pressed = true
			KEY_R:
				sim.init_wagon(sim.wagon_id, true)
			KEY_ENTER:
				if sim.mode == "REPLAY":
					_advance_next_wagon()
	elif event is InputEventKey and not event.pressed:
		if event.keycode in [KEY_W, KEY_UP, KEY_SPACE]:
			sim.jump_held = false

func _on_pointer_down(fid: int, pos: Vector2) -> void:
	if sim.mode == "TITLE":
		sim.start_game_from_title()
		return

	if sim.mode == "VICTORY":
		GameState.reset_campaign()
		sim.init_wagon(1)
		return

	# Replay controls
	if sim.mode == "REPLAY":
		for b in replay_buttons:
			if b["rect"].has_point(pos):
				match b["id"]:
					"rw_back":
						sim.replay_paused = true
						sim.replay_idx = maxi(0, sim.replay_idx - 18)
						sim._apply_snapshot(sim.recording[sim.replay_idx])
					"rw_pause":
						sim.replay_paused = not sim.replay_paused
					"rw_fwd":
						sim.replay_paused = true
						sim.replay_idx = mini(sim.recording.size() - 1, sim.replay_idx + 18)
						sim._apply_snapshot(sim.recording[sim.replay_idx])
					"rw_skip":
						_advance_next_wagon()
				return
		return

	# Interactive Idil radio choice (Wait vs Interrupt)
	if radio_prompt_active and not radio_choice_made:
		for db in dialogue_buttons:
			if db["rect"].has_point(pos):
				radio_choice_made = true
				radio_prompt_active = false
				GameState.radio_finished = true
				if db["id"] == "wait":
					GameState.radio_listened = true
					audio.play_sfx("radio", 0.0, 1.05)
				else:
					GameState.radio_interrupted = true
					audio.play_sfx("radio", 0.0, 0.85)
				return

	# Virtual HUD buttons
	for b in touch_buttons:
		if b["rect"].has_point(pos):
			var aid: String = b["id"]
			if aid == "mute":
				GameState.muted = not GameState.muted
				return
			active_touches[fid] = {"pos": pos, "action": aid}
			if aid == "slash":
				# Single tap executes immediately without waiting for release
				sim.queue_slash(Vector2(sim.player["facing"], 0))
			elif aid == "roll":
				sim.roll_pressed = true
			elif aid == "jump":
				sim.jump_held = true
				sim.jump_buffer = Simulation.JUMP_BUFFER_FRAMES
			elif aid == "use":
				sim.use_pressed = true
			_recompute_held_touch_state()
			return

	# Direct scene tap aims and slashes immediately toward tapped target
	var vp: Vector2 = get_viewport_rect().size
	var scale_f: float = minf(vp.x / 440.0, vp.y / Simulation.ROOM_H)
	var offset := Vector2((vp.x - 440.0 * scale_f) * 0.5, (vp.y - Simulation.ROOM_H * scale_f) * 0.5)
	var world_tap: Vector2 = (pos - offset) / scale_f + Vector2(sim.camera_x, 0.0)
	var aim: Vector2 = (world_tap - (sim.player["pos"] + Vector2(0, -13))).normalized()
	sim.aim_vec = aim
	sim.queue_slash(aim)
	# Walking while radio is active automatically interrupts Idil (narrative action choice)
	if radio_prompt_active and not radio_choice_made:
		radio_choice_made = true
		radio_prompt_active = false
		GameState.radio_finished = true
		GameState.radio_interrupted = true

func _on_pointer_drag(fid: int, pos: Vector2) -> void:
	if not active_touches.has(fid):
		return
	var cur_act: String = active_touches[fid]["action"]
	if cur_act in ["left", "right", "down"]:
		for b in touch_buttons:
			if b["id"] in ["left", "right", "down"] and b["rect"].has_point(pos):
				active_touches[fid]["action"] = b["id"]
				break
		_recompute_held_touch_state()

func _on_pointer_up(fid: int) -> void:
	if active_touches.has(fid):
		var act: String = active_touches[fid]["action"]
		active_touches.erase(fid)
		if act == "jump":
			sim.jump_held = false
		_recompute_held_touch_state()

func _recompute_held_touch_state() -> void:
	var dir := 0.0
	var down := false
	var focus := false
	for k in active_touches.keys():
		var a: String = active_touches[k]["action"]
		if a == "left":
			dir -= 1.0
		elif a == "right":
			dir += 1.0
		elif a == "down":
			down = true
		elif a == "focus":
			focus = true
	sim.input_dir = dir
	sim.input_down = down
	sim.input_focus = focus
	if absf(dir) > 0.1 and radio_prompt_active and not radio_choice_made:
		# Player can walk away without answering Idil -> counts as interrupting/skipping
		radio_choice_made = true
		radio_prompt_active = false
		GameState.radio_finished = true
		GameState.radio_interrupted = true

func _advance_next_wagon() -> void:
	if sim.wagon_id < 5:
		GameState.current_wagon = sim.wagon_id + 1
		sim.init_wagon(GameState.current_wagon)
	else:
		sim.mode = "VICTORY"

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	renderer.draw_world(self, sim, vp, font)

	if sim.mode == "PLAY":
		_draw_train_hud(vp)
		_draw_touch_controls()
		if radio_prompt_active and not radio_choice_made:
			_draw_radio_box(vp)
	elif sim.mode == "REPLAY":
		_draw_replay_controls()
	elif sim.mode == "VICTORY":
		_draw_victory_screen(vp)

func _draw_train_hud(vp: Vector2) -> void:
	# Railway control panel top bar (wagon indicator, focus gauge, held item icon)
	var panel := Rect2(22, 16, 360, 42)
	draw_rect(panel, Color(0.06, 0.11, 0.12, 0.88))
	draw_rect(panel, Color(0.80, 0.62, 0.24, 0.9), false, 2.0)

	var wagon_names := ["", "01 BILET", "02 YEMEK", "03 POSTA", "04 AKU", "05 LOKOMOTIF"]
	if font:
		draw_string(font, Vector2(34, 42), "VAGON %s" % wagon_names[sim.wagon_id], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.95, 0.84))

	# Focus bar
	var f_ratio: float = sim.focus_energy / Simulation.FOCUS_MAX
	draw_rect(Rect2(178, 28, 96, 16), Color(0.12, 0.18, 0.20))
	draw_rect(Rect2(178, 28, 96.0 * f_ratio, 16), Color(0.36, 0.89, 0.60))

	# Held item indicator
	var item_lbl := "-"
	if sim.player["held_item"] == "bottle":
		item_lbl = "SISE"
	elif sim.player["held_item"] == "knife":
		item_lbl = "BICAK"
	elif sim.player["held_item"] == "smoke":
		item_lbl = "DUMAN"
	if font:
		draw_string(font, Vector2(288, 42), "EL: %s" % item_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.95, 0.84))

	# Boss signal indicator in Wagon 5
	if sim.wagon_id == 5 and font:
		var sig_col := Color(0.90, 0.22, 0.27) if sim.boss_signal == "RED" else (Color(0.95, 0.82, 0.22) if sim.boss_signal == "YELLOW" else Color(0.36, 0.89, 0.60))
		draw_rect(Rect2(vp.x * 0.5 - 110, 16, 220, 36), Color(0.06, 0.11, 0.12, 0.9))
		draw_string(font, Vector2(vp.x * 0.5 - 96, 39), "SINYAL: %s" % sim.boss_signal, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, sig_col)

func _draw_radio_box(vp: Vector2) -> void:
	var box := Rect2(vp.x * 0.5 - 270, 66, 540, 114)
	draw_rect(box, Color(0.05, 0.10, 0.11, 0.94))
	draw_rect(box, Color(0.36, 0.89, 0.60), false, 2.0)
	if font:
		draw_string(font, Vector2(box.position.x + 18, box.position.y + 28), "TELSIZ [IDIL]: \"Camda kac isik saydin?\"", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.95, 0.84))
		draw_string(font, Vector2(box.position.x + 18, box.position.y + 50), "(Beklersen Posta Vagonu personel gecidini tarif edecek)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.36, 0.89, 0.60))
	for db in dialogue_buttons:
		draw_rect(db["rect"], Color(0.14, 0.24, 0.23))
		draw_rect(db["rect"], Color(0.80, 0.62, 0.24), false, 2.0)
		if font:
			draw_string(font, db["rect"].position + Vector2(16, 28), db["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.95, 0.84))

func _draw_touch_controls() -> void:
	for b in touch_buttons:
		var r: Rect2 = b["rect"]
		var is_slash: bool = (b["id"] == "slash")
		var bg := Color(0.24, 0.10, 0.12, 0.52) if is_slash else Color(0.08, 0.15, 0.16, 0.52)
		var border := Color(0.90, 0.22, 0.27, 0.82) if is_slash else Color(0.80, 0.62, 0.24, 0.72)
		draw_rect(r, bg)
		draw_rect(r, border, false, 2.0)
		if font:
			draw_string(font, r.position + Vector2(14, r.size.y * 0.58), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.95, 0.84))

func _draw_replay_controls() -> void:
	for b in replay_buttons:
		var r: Rect2 = b["rect"]
		draw_rect(r, Color(0.07, 0.13, 0.14, 0.90))
		draw_rect(r, Color(0.36, 0.89, 0.60), false, 2.0)
		if font:
			draw_string(font, r.position + Vector2(14, 32), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.95, 0.84))

func _draw_victory_screen(vp: Vector2) -> void:
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.04, 0.07, 0.09, 0.92))
	var truth_known: bool = GameState.radio_listened or GameState.found_shift_manifest
	var line1 := "SON HAT TAMAMLANDI  //  LOKOMOTIF DURDURULDU"
	var line2 := "IDIL'IN HATIRASI DOGRULANDI: EKSIK VARDIYA KAYDI ORTAYA CIKTI." if truth_known else "MAKINIST KABINI ELE GECIRILDI, ANCAK KAYIP ISIM SIRRI KALDI."
	if font:
		draw_string(font, Vector2(vp.x * 0.5 - 240, vp.y * 0.38), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.36, 0.89, 0.60))
		draw_string(font, Vector2(vp.x * 0.5 - 270, vp.y * 0.48), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.95, 0.84))
		draw_string(font, Vector2(vp.x * 0.5 - 150, vp.y * 0.62), "YENIDEN OYNAMAK ICIN DOKUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.80, 0.62, 0.24))

func _run_headless_verification() -> void:
	var s := Simulation.new()
	# Test 1: Slash input buffer (2 frames before cooldown -> 1 hit; 5 frames before -> 0 hit)
	s.init_wagon(1, true)
	s.player["slash_cd"] = 5
	s.queue_slash(Vector2.RIGHT)
	assert(s.slash_buffer == 0, "5 frames early slash must not buffer")
	s.player["slash_cd"] = 2
	s.queue_slash(Vector2.RIGHT)
	assert(s.slash_buffer == Simulation.SLASH_BUFFER_WINDOW, "2 frames early slash must buffer")
	s.step_fixed()
	s.step_fixed()
	assert(s.player["slash_timer"] > 0, "Buffered slash must fire on first eligible frame")

	# Test 2: Roll pickup at x=44 collects bottle at x=66; walking leaves it on floor
	s.init_wagon(1, true)
	s.input_dir = 1.0
	for _i in range(18):
		s.step_fixed()
	assert(s.player["held_item"] == "", "Walking past bottle must leave it on floor")
	s.init_wagon(1, true)
	s.roll_pressed = true
	for _i in range(18):
		s.step_fixed()
	assert(s.player["held_item"] == "bottle", "Rolling from x=44 must collect bottle at x=66")

	# Test 3: Replay 1x world-time normalization (2s normal + 2s 0.30x focus + 1s normal = ~3.60s)
	s.init_wagon(2, true)
	for _i in range(120):
		s.step_fixed()
	s.input_focus = true
	for _i in range(120):
		s.step_fixed()
	s.input_focus = false
	for _i in range(60):
		s.step_fixed()
	var total_w := 0.0
	for snap in s.recording:
		total_w += snap["world_dt"]
	assert(absf(total_w - 3.60) < 0.05, "Replay normalized world time should be ~3.60s")
	print("ALL GODOT 4.3 HEADLESS VERIFICATION TESTS PASSED!")
