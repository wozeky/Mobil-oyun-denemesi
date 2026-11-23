extends RefCounted
class_name Simulation

# Fixed 60 Hz simulation constants (Son Hat design values)
const FIXED_DT: float = 1.0 / 60.0
const SLASH_ACTIVE_FRAMES: int = 10
const SLASH_COOLDOWN_FRAMES: int = 17
const SLASH_BUFFER_WINDOW: int = 3
const COYOTE_FRAMES: int = 5
const JUMP_BUFFER_FRAMES: int = 5
const ROLL_DURATION: int = 18
const ROLL_IFRAME_START: int = 2
const ROLL_IFRAME_END: int = 13
const ROLL_SPEED: float = 136.0 # ~2.266 px/frame -> x=44 roll crosses x=66 bottle cleanly
const WALK_SPEED: float = 112.0
const GRAVITY: float = 780.0
const JUMP_VEL: float = -275.0
const FOCUS_SCALE: float = 0.30
const FOCUS_MAX: float = 180.0 # 3 seconds of focus energy

# Room coordinate space: logical pixels (rendered at 2.5x = 1280x720)
const ROOM_W: float = 512.0
const ROOM_H: float = 240.0
const FLOOR_Y: float = 204.0

var wagon_id: int = 1
var sim_tick: int = 0
var world_time: float = 0.0
var hitstop_frames: int = 0
var focus_active: bool = false
var focus_energy: float = FOCUS_MAX
var slow_accum: float = 0.0

var mode: String = "PLAY" # TITLE, PLAY, DEAD_REWIND, REPLAY, DIALOGUE, VICTORY
var level_clear_delay: int = 0
var camera_x: float = 0.0
var shake_frames: int = 0
var shake_dir: Vector2 = Vector2.ZERO

# Player state
var player: Dictionary = {}

# Input state (updated by Main.gd or deterministic test harness)
var input_dir: float = 0.0
var input_down: bool = false
var input_focus: bool = false
var jump_held: bool = false
var jump_buffer: int = 0
var slash_buffer: int = 0
var buffered_aim: Vector2 = Vector2.RIGHT
var slash_held: bool = false
var roll_pressed: bool = false
var use_pressed: bool = false
var aim_vec: Vector2 = Vector2.RIGHT

# World entities
var walls: Array[Rect2] = []
var one_way_platforms: Array[Rect2] = []
var doors: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var items: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var barrels: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var cameras: Array[Dictionary] = []
var power_panel: Dictionary = {}
var turret: Dictionary = {}
var exit_zone: Rect2 = Rect2()
var alt_exit_zone: Rect2 = Rect2()
var interact_sign: Dictionary = {}

# Visual & audio event logs for current frame
var frame_events: Array[Dictionary] = []
var blood_decals: Array[Dictionary] = [] # persistent marks; indexed by count in snapshots!
var slash_fx: Dictionary = {}
var clash_sparks: Array[Dictionary] = []

# Recording / Rewind / Replay buffers (O(1) decal count reference -> tiny memory footprint)
var recording: Array[Dictionary] = []
var replay_idx: int = 0
var replay_paused: bool = false
var replay_accum: float = 0.0

# Intro sequence state (plays once per session)
var intro_timer: int = 0
var intro_extra_lamp_x: float = -40.0
var intro_footstep_timer: int = 0
var door1_glint_timer: int = 0

# Boss (Chief Engineer) state
var boss_phase: int = 1
var boss_signal: String = "RED" # RED (rush slash), YELLOW (teleport cross), GREEN (volley)
var boss_timer: int = 75
var boss_telegraph_pos: Vector2 = Vector2.ZERO

func init_wagon(id: int, skip_intro: bool = false) -> void:
	wagon_id = clampi(id, 1, 5)
	sim_tick = 0
	world_time = 0.0
	hitstop_frames = 0
	focus_active = false
	focus_energy = FOCUS_MAX
	slow_accum = 0.0
	level_clear_delay = 0
	shake_frames = 0
	shake_dir = Vector2.ZERO

	input_dir = 0.0
	input_down = false
	input_focus = false
	jump_held = false
	jump_buffer = 0
	slash_buffer = 0
	slash_held = false
	roll_pressed = false
	use_pressed = false
	aim_vec = Vector2.RIGHT

	walls.clear()
	one_way_platforms.clear()
	doors.clear()
	enemies.clear()
	items.clear()
	bullets.clear()
	barrels.clear()
	smokes.clear()
	cameras.clear()
	power_panel = {}
	turret = {}
	interact_sign = {}
	frame_events.clear()
	blood_decals.clear()
	slash_fx = {}
	clash_sparks.clear()
	recording.clear()
	replay_idx = 0
	replay_paused = false
	replay_accum = 0.0

	_build_wagon(wagon_id)
	if skip_intro:
		mode = "PLAY"
	else:
		mode = "TITLE" if (wagon_id == 1 and not GameState.intro_played) else "PLAY"
	intro_timer = 0
	intro_extra_lamp_x = -20.0
	intro_footstep_timer = 0
	door1_glint_timer = 0

	_record_snapshot(0.0)

func _make_player(px: float, py: float) -> Dictionary:
	return {
		"pos": Vector2(px, py),
		"vel": Vector2.ZERO,
		"facing": 1,
		"on_ground": true,
		"on_wall": 0,
		"coyote": 0,
		"drop_through": 0,
		"roll_timer": 0,
		"roll_dir": 1,
		"slash_timer": 0,
		"slash_cd": 0,
		"slash_dir": Vector2.RIGHT,
		"slash_hit_ids": [],
		"held_item": "", # "", "bottle", "knife", "smoke"
		"alive": true,
		"lamp_sway": 0.0,
		"prev_vx": 0.0,
		"anim": "idle",
		"anim_frame": 0,
	}

func _build_wagon(id: int) -> void:
	# Outer train car boundaries
	walls.append(Rect2(-16, 0, 16, ROOM_H))
	walls.append(Rect2(ROOM_W, 0, 16, ROOM_H))
	walls.append(Rect2(0, 0, ROOM_W, 24))
	walls.append(Rect2(0, FLOOR_Y, ROOM_W, 36))

	match id:
		1:
			# WAGON 1: BILET KONTROLU (Ticket Control)
			# Player starts at x=44 so a roll right crosses the bottle at x=66 cleanly
			player = _make_player(44.0, FLOOR_Y)
			items.append({"id": 1, "type": "bottle", "pos": Vector2(66.0, FLOOR_Y - 6.0), "vel": Vector2.ZERO, "thrown": false, "owner": "none", "active": true})
			doors.append({"id": 1, "x": 116.0, "y": FLOOR_Y - 42.0, "w": 10.0, "h": 42.0, "open": false, "open_dir": 1, "frosted": true})
			enemies.append(_make_enemy(1, "melee", 136.0, FLOOR_Y, -1))
			enemies.append(_make_enemy(2, "pistol", 252.0, FLOOR_Y, -1))
			one_way_platforms.append(Rect2(170.0, 148.0, 74.0, 6.0))
			exit_zone = Rect2(468.0, FLOOR_Y - 44.0, 28.0, 44.0)
			interact_sign = {"x": 96.0, "y": FLOOR_Y - 54.0, "text": "KAPIYI KES VEYA SISEYI TAKLADA AL"}
		2:
			# WAGON 2: YEMEK VAGONU (Dining Car - counter cover, 3 routes)
			player = _make_player(36.0, FLOOR_Y)
			# Service counter blocks line of sight and bullets cleanly without corner ghost hits
			walls.append(Rect2(146.0, FLOOR_Y - 24.0, 44.0, 24.0))
			one_way_platforms.append(Rect2(138.0, 142.0, 64.0, 6.0))
			items.append({"id": 10, "type": "knife", "pos": Vector2(88.0, FLOOR_Y - 6.0), "vel": Vector2.ZERO, "thrown": false, "owner": "none", "active": true})
			enemies.append(_make_enemy(10, "pistol", 274.0, FLOOR_Y, -1))
			enemies.append(_make_enemy(11, "shield", 368.0, FLOOR_Y, -1))
			exit_zone = Rect2(468.0, FLOOR_Y - 44.0, 28.0, 44.0)
			interact_sign = {"x": 124.0, "y": FLOOR_Y - 54.0, "text": "TEZGAH SIPERI: USTTEN ATLA, MERMI SEKTIR VEYA BICAK AT"}
		3:
			# WAGON 3: POSTA VAGONU (Mail Car - Idil's radio memory payoff)
			player = _make_player(36.0, FLOOR_Y)
			one_way_platforms.append(Rect2(96.0, 144.0, 76.0, 6.0))   # RAF-A
			one_way_platforms.append(Rect2(204.0, 128.0, 82.0, 6.0))  # RAF-B (Shift manifest)
			one_way_platforms.append(Rect2(318.0, 144.0, 84.0, 6.0))  # RAF-C (Staff hatch if listened)
			items.append({"id": 20, "type": "smoke", "pos": Vector2(118.0, 138.0), "vel": Vector2.ZERO, "thrown": false, "owner": "none", "active": true})
			enemies.append(_make_enemy(20, "shotgun", 242.0, FLOOR_Y, -1))
			enemies.append(_make_enemy(21, "melee", 348.0, FLOOR_Y, -1))
			exit_zone = Rect2(468.0, FLOOR_Y - 44.0, 28.0, 44.0)
			alt_exit_zone = Rect2(342.0, 102.0, 34.0, 42.0) # Upper staff passage unlocked if player waited for Idil
			interact_sign = {"x": 226.0, "y": 116.0, "text": "VARDIYA CIZELGESI: ISIM SILINMIS"}
		4:
			# WAGON 4: AKU DAIRESI (Battery Room - Camera + Cable + Turret + Panel + Barrels)
			player = _make_player(36.0, FLOOR_Y)
			cameras.append({"id": 1, "pos": Vector2(168.0, 44.0), "dir": -1, "sweep": 0.0, "alert": 0})
			turret = {"pos": Vector2(312.0, 48.0), "powered": false, "cable_charge": 0.0, "cooldown": 25, "alive": true}
			power_panel = {"pos": Vector2(214.0, FLOOR_Y - 22.0), "w": 16.0, "h": 22.0, "active": true}
			barrels.append({"id": 1, "pos": Vector2(348.0, FLOOR_Y - 18.0), "intact": true, "fuse": 0})
			barrels.append({"id": 2, "pos": Vector2(382.0, FLOOR_Y - 18.0), "intact": true, "fuse": 0})
			enemies.append(_make_enemy(30, "shield", 364.0, FLOOR_Y, -1))
			enemies.append(_make_enemy(31, "pistol", 432.0, FLOOR_Y, -1))
			exit_zone = Rect2(468.0, FLOOR_Y - 44.0, 28.0, 44.0)
		5:
			# WAGON 5: LOKOMOTIF (Chief Engineer 3-phase signal fight)
			player = _make_player(44.0, FLOOR_Y)
			one_way_platforms.append(Rect2(116.0, 146.0, 74.0, 6.0))
			one_way_platforms.append(Rect2(314.0, 146.0, 74.0, 6.0))
			var boss := _make_enemy(99, "boss", 386.0, FLOOR_Y, -1)
			boss["hp"] = 3
			boss["max_hp"] = 3
			enemies.append(boss)
			boss_phase = 1
			boss_signal = "RED"
			boss_timer = 70
			exit_zone = Rect2(468.0, FLOOR_Y - 44.0, 28.0, 44.0)

func _make_enemy(id: int, etype: String, ex: float, ey: float, facing: int) -> Dictionary:
	return {
		"id": id,
		"type": etype, # melee, pistol, shotgun, shield, boss
		"pos": Vector2(ex, ey),
		"vel": Vector2.ZERO,
		"facing": facing,
		"alive": true,
		"hp": 1,
		"stun": 0,
		"windup": 0,
		"windup_max": 24,
		"recover": 0,
		"turn_window": 0,
		"alert_pos": Vector2(-1, -1),
		"aim_dir": Vector2(facing, 0),
		"shield_up": (etype == "shield"),
		"telegraph_alpha": 0.0,
	}

func start_game_from_title() -> void:
	if mode == "TITLE":
		mode = "PLAY"
		if wagon_id == 1 and not GameState.intro_played:
			GameState.intro_played = true
			GameState.radio_started = true
			frame_events.append({"type": "sfx", "name": "radio", "pan": 0.0})

func queue_slash(dir: Vector2) -> void:
	if mode != "PLAY" or not player["alive"]:
		return
	var norm_dir := dir.normalized() if dir.length() > 0.05 else Vector2(player["facing"], 0.0)
	# Reliable 3-frame input buffer before roll or attack cooldown finishes
	var can_now: bool = (player["roll_timer"] == 0 and player["slash_cd"] == 0)
	var within_buffer: bool = (
		(player["roll_timer"] > 0 and player["roll_timer"] <= SLASH_BUFFER_WINDOW) or
		(player["slash_cd"] > 0 and player["slash_cd"] <= SLASH_BUFFER_WINDOW)
	)
	if can_now or within_buffer:
		slash_buffer = SLASH_BUFFER_WINDOW
		buffered_aim = norm_dir

func clear_buffered_commands() -> void:
	slash_buffer = 0
	jump_buffer = 0
	roll_pressed = false
	use_pressed = false

func step_fixed() -> void:
	frame_events.clear()

	# Title screen ambient train motion
	if mode == "TITLE":
		sim_tick += 1
		return

	if mode == "DEAD_REWIND":
		# Rewind 3 recorded frames per tick until frame 0
		for _i in range(3):
			if replay_idx > 0:
				replay_idx -= 1
				_apply_snapshot(recording[replay_idx])
		if replay_idx <= 0:
			init_wagon(wagon_id, true)
		return

	if mode == "REPLAY":
		if not replay_paused and recording.size() > 0:
			# Normalize replay to 1x real world speed even through focus segments
			replay_accum += FIXED_DT
			while replay_idx < recording.size() - 1:
				var frame_world_dt: float = recording[replay_idx + 1]["world_dt"]
				if replay_accum + 0.000001 < frame_world_dt:
					break
				replay_accum = maxf(0.0, replay_accum - frame_world_dt)
				replay_idx += 1
				_apply_snapshot(recording[replay_idx])
		return

	if mode != "PLAY":
		return

	# Level clear celebration buffer before CCTV replay starts (gives last hit time to breathe)
	if level_clear_delay > 0:
		level_clear_delay -= 1
		if hitstop_frames > 0:
			hitstop_frames -= 1
		_record_snapshot(FIXED_DT)
		if level_clear_delay == 0:
			mode = "REPLAY"
			replay_idx = 0
			replay_paused = false
			replay_accum = 0.0
			_apply_snapshot(recording[0])
		return

	# Hitstop freezes physics briefly while still honoring valid single tap buffers
	if hitstop_frames > 0:
		hitstop_frames -= 1
		_record_snapshot(FIXED_DT)
		return

	# Focus time scaling (0.30x world clock)
	var wants_focus := input_focus and focus_energy > 1.0
	if wants_focus:
		focus_active = true
		focus_energy = maxf(0.0, focus_energy - 1.0)
	else:
		focus_active = false
		focus_energy = minf(FOCUS_MAX, focus_energy + 0.55)

	var time_scale: float = FOCUS_SCALE if focus_active else 1.0
	slow_accum += time_scale
	if slow_accum + 0.000001 < 1.0:
		return
	slow_accum = maxf(0.0, slow_accum - 1.0)

	sim_tick += 1
	world_time += FIXED_DT

	# Wagon 1 first-minute scripted atmosphere cues
	if wagon_id == 1:
		intro_timer += 1
		if intro_timer == 95:
			intro_extra_lamp_x = ROOM_W + 24.0
		if intro_extra_lamp_x > -40.0:
			intro_extra_lamp_x -= 14.0
		if not doors[0]["open"]:
			intro_footstep_timer += 1
			if intro_footstep_timer % 34 == 0:
				frame_events.append({"type": "sfx", "name": "footstep", "pan": 0.72})
		if door1_glint_timer > 0:
			door1_glint_timer -= 1

	_update_player()
	_update_projectiles()
	_update_enemies()
	_update_hazards()
	_update_fx()

	# Smooth camera tracking that leaves room ahead of player's slash direction
	var look_ahead: float = float(player["facing"]) * 38.0
	var target_cam: float = clampf(player["pos"].x + look_ahead - 220.0, 0.0, maxf(0.0, ROOM_W - 440.0))
	camera_x = lerpf(camera_x, target_cam, 0.16)

	_record_snapshot(FIXED_DT)

	# Check wagon completion
	if player["alive"] and _check_wagon_cleared():
		clear_buffered_commands()
		level_clear_delay = 28 # ~0.46s breathing room for final hitstop & cloth trail before CCTV replay

func _update_player() -> void:
	if not player["alive"]:
		return

	if player["slash_cd"] > 0:
		player["slash_cd"] -= 1
	if player["slash_timer"] > 0:
		player["slash_timer"] -= 1
	if player["drop_through"] > 0:
		player["drop_through"] -= 1
	if jump_buffer > 0:
		jump_buffer -= 1

	# Roll initiation
	if roll_pressed and player["roll_timer"] == 0 and player["on_ground"]:
		roll_pressed = false
		player["roll_timer"] = ROLL_DURATION
		var rdir: int = int(signf(input_dir)) if absf(input_dir) > 0.1 else int(player["facing"])
		player["roll_dir"] = rdir
		player["facing"] = rdir
		player["anim"] = "roll"
	else:
		roll_pressed = false

	# Execute buffered slash on earliest valid frame
	if slash_buffer > 0:
		if player["roll_timer"] == 0 and player["slash_cd"] == 0:
			slash_buffer = 0
			_perform_slash(buffered_aim)
		else:
			slash_buffer -= 1

	# Use / Throw / Manual Pickup
	if use_pressed:
		use_pressed = false
		if player["held_item"] != "":
			_throw_held_item()
		else:
			_try_pickup_item(24.0)

	# Horizontal movement
	if player["roll_timer"] > 0:
		player["roll_timer"] -= 1
		player["vel"].x = float(player["roll_dir"]) * ROLL_SPEED
		# Pickup portable item automatically during roll if hands are empty
		if player["held_item"] == "":
			_try_pickup_item(18.0)
	elif player["slash_timer"] > 6:
		# Brief slash lunge momentum preserved (not overwritten by walk)
		pass
	else:
		if absf(input_dir) > 0.1:
			player["vel"].x = signf(input_dir) * WALK_SPEED
			if player["slash_timer"] == 0:
				player["facing"] = int(signf(input_dir))
		else:
			# Immediate crisp stop on direction release
			player["vel"].x = 0.0

	# Shoulder lamp 1-frame inertial swing on sudden stop
	var accel: float = player["vel"].x - player["prev_vx"]
	player["lamp_sway"] = clampf(-accel * 0.035, -3.5, 3.5)
	player["prev_vx"] = player["vel"].x

	# One-way platform drop-through
	if input_down and player["on_ground"] and jump_buffer > 0:
		jump_buffer = 0
		player["drop_through"] = 10
		player["on_ground"] = false
		player["pos"].y += 2.0

	# Jump (coyote time + wall jump + variable jump height)
	if jump_buffer > 0:
		if player["on_ground"] or player["coyote"] > 0:
			jump_buffer = 0
			player["coyote"] = 0
			player["on_ground"] = false
			player["vel"].y = JUMP_VEL
		elif player["on_wall"] != 0:
			jump_buffer = 0
			var wdir: int = -int(player["on_wall"])
			player["facing"] = wdir
			player["vel"].x = float(wdir) * (WALK_SPEED * 1.15)
			player["vel"].y = JUMP_VEL * 0.92
			player["on_wall"] = 0

	# Variable jump cut on early release
	if not jump_held and player["vel"].y < -110.0:
		player["vel"].y *= 0.65

	# Gravity & wall slide
	var grav: float = GRAVITY
	if player["on_wall"] != 0 and player["vel"].y > 0.0 and not player["on_ground"]:
		grav = GRAVITY * 0.32
		player["vel"].y = minf(player["vel"].y, 58.0)
	player["vel"].y += grav * FIXED_DT

	# Move & collide X
	player["pos"].x += player["vel"].x * FIXED_DT
	player["on_wall"] = 0
	var pbox := _player_rect(player["pos"])
	for w in walls:
		if pbox.intersects(w):
			if player["vel"].x > 0.0:
				player["pos"].x = w.position.x - 6.0
				player["on_wall"] = 1
			elif player["vel"].x < 0.0:
				player["pos"].x = w.end.x + 6.0
				player["on_wall"] = -1
			player["vel"].x = 0.0
			pbox = _player_rect(player["pos"])

	# Closed doors block walking until slashed/kicked open
	for d in doors:
		if not d["open"]:
			var drect := Rect2(d["x"], d["y"], d["w"], d["h"])
			if pbox.intersects(drect):
				if player["vel"].x > 0.0:
					player["pos"].x = drect.position.x - 6.0
				elif player["vel"].x < 0.0:
					player["pos"].x = drect.end.x + 6.0
				player["vel"].x = 0.0
				pbox = _player_rect(player["pos"])

	# Move & collide Y
	var prev_y: float = player["pos"].y
	player["pos"].y += player["vel"].y * FIXED_DT
	var was_grounded: bool = player["on_ground"]
	player["on_ground"] = false
	pbox = _player_rect(player["pos"])

	for w in walls:
		if pbox.intersects(w):
			if player["vel"].y >= 0.0:
				player["pos"].y = w.position.y
				player["vel"].y = 0.0
				player["on_ground"] = true
			elif player["vel"].y < 0.0:
				player["pos"].y = w.end.y + 24.0
				player["vel"].y = 0.0
			pbox = _player_rect(player["pos"])

	if player["vel"].y >= 0.0 and player["drop_through"] == 0:
		for plat in one_way_platforms:
			if prev_y <= plat.position.y + 2.0 and player["pos"].y >= plat.position.y:
				if player["pos"].x + 5.0 >= plat.position.x and player["pos"].x - 5.0 <= plat.end.x:
					player["pos"].y = plat.position.y
					player["vel"].y = 0.0
					player["on_ground"] = true

	if player["on_ground"]:
		player["coyote"] = COYOTE_FRAMES
	elif was_grounded and player["vel"].y >= 0.0:
		player["coyote"] = COYOTE_FRAMES
	elif player["coyote"] > 0:
		player["coyote"] -= 1

	# Animation state selection
	if player["roll_timer"] > 0:
		player["anim"] = "roll"
	elif player["slash_timer"] > 0:
		player["anim"] = "slash"
	elif player["on_wall"] != 0 and not player["on_ground"]:
		player["anim"] = "wall"
	elif absf(player["vel"].x) > 5.0:
		player["anim"] = "run"
		player["anim_frame"] = 1 if ((sim_tick / 6) % 2 == 0) else 2
	else:
		player["anim"] = "idle"
		player["anim_frame"] = 0

	# Active slash arc check (frames 1..10 of slash)
	if player["slash_timer"] > 0:
		_process_active_slash()

func _perform_slash(dir: Vector2) -> void:
	player["slash_timer"] = SLASH_ACTIVE_FRAMES
	player["slash_cd"] = SLASH_COOLDOWN_FRAMES
	player["slash_dir"] = dir
	player["slash_hit_ids"] = []
	if absf(dir.x) > 0.15:
		player["facing"] = int(signf(dir.x))
	# Crisp directional lunge (diagonal air slash supported)
	player["vel"].x = dir.x * 165.0
	if not player["on_ground"] and dir.y < -0.2:
		player["vel"].y = minf(player["vel"].y, dir.y * 140.0)

	var origin: Vector2 = player["pos"] + Vector2(0, -13)
	slash_fx = {
		"origin": origin,
		"dir": dir,
		"timer": SLASH_ACTIVE_FRAMES,
		"outcome": "whiff", # upgraded to hit/block/clash/deflect on contact
	}
	frame_events.append({"type": "sfx", "name": "whiff", "pan": 0.0})

func _process_active_slash() -> void:
	var origin: Vector2 = player["pos"] + Vector2(0, -13)
	var sdir: Vector2 = player["slash_dir"]
	var reach: float = 34.0
	slash_fx["origin"] = origin

	# 1. Doors (kicking/slashing open stuns guard right behind door)
	for d in doors:
		if not d["open"]:
			var dcenter := Vector2(d["x"] + d["w"] * 0.5, d["y"] + d["h"] * 0.5)
			if origin.distance_to(dcenter) <= reach + 8.0 and (dcenter - origin).normalized().dot(sdir) > 0.25:
				d["open"] = true
				d["open_dir"] = int(signf(sdir.x)) if absf(sdir.x) > 0.1 else 1
				door1_glint_timer = 22
				frame_events.append({"type": "sfx", "name": "door", "pan": 0.0})
				for e in enemies:
					if e["alive"] and absf(e["pos"].x - d["x"]) < 36.0:
						e["stun"] = 90 # 1.5s stun from door slam
						e["shield_up"] = false
				_alert_enemies_at(dcenter)

	# 2. Power panel (Wagon 4)
	if power_panel.get("active", false):
		var pcenter: Vector2 = power_panel["pos"] + Vector2(8, 11)
		if origin.distance_to(pcenter) <= reach and (pcenter - origin).normalized().dot(sdir) > 0.2:
			power_panel["active"] = false
			if turret.has("powered"):
				turret["powered"] = false
			hitstop_frames = 3
			frame_events.append({"type": "sfx", "name": "clash", "pan": 0.0})

	# 3. Explosive barrels
	for b in barrels:
		if b["intact"] and origin.distance_to(b["pos"]) <= reach:
			_detonate_barrel(b)

	# 4. Enemies (each swing hits a target at most once; solid walls block arc)
	for e in enemies:
		if not e["alive"] or e["id"] in player["slash_hit_ids"]:
			continue
		var ecenter: Vector2 = e["pos"] + Vector2(0, -13)
		var to_e: Vector2 = ecenter - origin
		if to_e.length() > reach:
			continue
		if to_e.normalized().dot(sdir) < 0.35:
			continue
		if _segment_hits_wall(origin, ecenter):
			continue

		player["slash_hit_ids"].append(e["id"])

		# Sword clash if melee/boss enemy is actively swinging toward player
		if (e["type"] == "melee" or e["type"] == "boss") and e["windup"] > 0 and e["windup"] <= 8:
			slash_fx["outcome"] = "clash"
			hitstop_frames = 5
			player["vel"].x = -float(player["facing"]) * 120.0
			e["vel"].x = float(player["facing"]) * 110.0
			e["windup"] = 0
			e["recover"] = 24
			clash_sparks.append({"pos": (origin + ecenter) * 0.5, "timer": 14, "kind": "clash"})
			frame_events.append({"type": "sfx", "name": "clash", "pan": 0.0})
			continue

		# Shield block if enemy faces player and shield is raised
		if e["type"] == "shield" and e["shield_up"] and e["turn_window"] == 0 and signf(origin.x - e["pos"].x) == float(e["facing"]):
			slash_fx["outcome"] = "block"
			hitstop_frames = 4
			player["vel"].x = -float(player["facing"]) * 105.0
			clash_sparks.append({"pos": ecenter + Vector2(e["facing"] * 7, 0), "timer": 12, "kind": "block"})
			frame_events.append({"type": "sfx", "name": "block", "pan": 0.0})
			continue

		# Clean hit!
		slash_fx["outcome"] = "hit"
		hitstop_frames = 5
		shake_frames = 6
		shake_dir = sdir
		_damage_enemy(e, sdir)

func _damage_enemy(e: Dictionary, dir: Vector2) -> void:
	e["hp"] -= 1
	if e["hp"] <= 0:
		e["alive"] = false
		blood_decals.append({"pos": e["pos"], "dir": dir, "len": 18.0 + float((e["id"] * 7) % 10)})
		frame_events.append({"type": "sfx", "name": "hit", "pan": clampf((e["pos"].x - player["pos"].x) / 220.0, -0.8, 0.8)})
	else:
		# Chief Engineer phase transition
		e["stun"] = 20
		boss_phase += 1
		boss_signal = "YELLOW" if boss_phase == 2 else "GREEN"
		boss_timer = 55
		frame_events.append({"type": "sfx", "name": "hit", "pan": 0.0})

func _try_pickup_item(radius: float) -> void:
	for it in items:
		if it["active"] and not it["thrown"] and it["owner"] == "none":
			if absf(it["pos"].x - player["pos"].x) <= radius and absf(it["pos"].y - player["pos"].y) <= 22.0:
				player["held_item"] = it["type"]
				it["active"] = false
				it["owner"] = "player"
				frame_events.append({"type": "sfx", "name": "pickup", "pan": 0.0})
				return

func _throw_held_item() -> void:
	var ttype: String = player["held_item"]
	player["held_item"] = ""
	var tdir: Vector2 = aim_vec.normalized() if aim_vec.length() > 0.1 else Vector2(player["facing"], 0.0)
	if absf(tdir.y) < 0.15:
		tdir = Vector2(signf(tdir.x) if absf(tdir.x) > 0.05 else float(player["facing"]), -0.04).normalized()
	items.append({
		"id": 500 + sim_tick,
		"type": ttype,
		"pos": player["pos"] + Vector2(player["facing"] * 8.0, -14.0),
		"vel": tdir * 310.0,
		"thrown": true,
		"owner": "player",
		"active": true,
	})
	frame_events.append({"type": "sfx", "name": "whiff", "pan": 0.0, "pitch": 1.25})

func _update_projectiles() -> void:
	# 1. Thrown items
	for it in items:
		if it["active"] and it["thrown"]:
			var p0: Vector2 = it["pos"]
			var p1: Vector2 = p0 + it["vel"] * FIXED_DT
			it["pos"] = p1
			if _segment_hits_wall(p0, p1) or p1.x < 0.0 or p1.x > ROOM_W:
				it["active"] = false
				if it["type"] == "smoke":
					smokes.append({"pos": p0, "timer": 240, "max_timer": 240, "radius": 44.0})
				frame_events.append({"type": "sfx", "name": "block", "pan": 0.0, "pitch": 1.4})
				continue
			for e in enemies:
				if e["alive"] and _segment_hits_rect(p0, p1, Rect2(e["pos"].x - 7, e["pos"].y - 24, 14, 24)):
					it["active"] = false
					if it["type"] == "knife":
						_damage_enemy(e, it["vel"].normalized())
					elif it["type"] == "smoke":
						smokes.append({"pos": e["pos"], "timer": 240, "max_timer": 240, "radius": 44.0})
					else:
						# Bottle stuns & shatters on target
						e["stun"] = 120
						e["shield_up"] = false
						hitstop_frames = 3
						frame_events.append({"type": "sfx", "name": "hit", "pan": 0.0, "pitch": 1.3})
					break

	# 2. Bullets (Swept-segment collision with strict priority: Wall > Slash Deflect > Actor)
	for b in bullets:
		if not b["active"]:
			continue
		var p0: Vector2 = b["pos"]
		var p1: Vector2 = p0 + b["vel"] * FIXED_DT
		var wall_hit = _segment_wall_point(p0, p1)
		var deflect_hit: bool = false
		if b["owner"] == "enemy" and player["slash_timer"] > 0:
			var s_orig: Vector2 = player["pos"] + Vector2(0, -13)
			var mid: Vector2 = (p0 + p1) * 0.5
			if s_orig.distance_to(mid) <= 34.0 and (mid - s_orig).normalized().dot(player["slash_dir"]) > 0.15:
				deflect_hit = true

		# Priority 1: Solid wall/counter stops bullet cleanly at surface with spark
		if wall_hit != null and (not deflect_hit or p0.distance_to(wall_hit) <= p0.distance_to(player["pos"])):
			b["active"] = false
			clash_sparks.append({"pos": wall_hit, "timer": 10, "kind": "wall"})
			continue

		# Priority 2: Sword deflection turns bullet into player-owned projectile in aimed direction
		if deflect_hit:
			b["owner"] = "player"
			var rdir: Vector2 = player["slash_dir"].normalized()
			b["vel"] = rdir * b["vel"].length() * 1.15
			b["pos"] = p0 + rdir * 8.0
			slash_fx["outcome"] = "deflect"
			hitstop_frames = 4
			clash_sparks.append({"pos": b["pos"], "timer": 12, "kind": "deflect"})
			frame_events.append({"type": "sfx", "name": "deflect", "pan": 0.0})
			continue

		b["pos"] = p1
		if p1.x < -16.0 or p1.x > ROOM_W + 16.0 or p1.y < 0.0 or p1.y > ROOM_H:
			b["active"] = false
			continue

		# Barrel hit
		for bar in barrels:
			if bar["intact"] and _segment_hits_rect(p0, p1, Rect2(bar["pos"].x - 6, bar["pos"].y - 9, 12, 18)):
				b["active"] = false
				_detonate_barrel(bar)
				break
		if not b["active"]:
			continue

		# Actor hit
		if b["owner"] == "enemy":
			var invuln: bool = (player["roll_timer"] >= ROLL_IFRAME_START and player["roll_timer"] <= ROLL_IFRAME_END)
			if not invuln and _segment_hits_rect(p0, p1, _player_rect(player["pos"])):
				b["active"] = false
				_kill_player()
		else:
			for e in enemies:
				if e["alive"] and _segment_hits_rect(p0, p1, Rect2(e["pos"].x - 7, e["pos"].y - 24, 14, 24)):
					b["active"] = false
					if e["type"] == "shield" and e["shield_up"] and signf(p0.x - e["pos"].x) == float(e["facing"]):
						frame_events.append({"type": "sfx", "name": "block", "pan": 0.0})
					else:
						_damage_enemy(e, b["vel"].normalized())
					break

func _update_enemies() -> void:
	for e in enemies:
		if not e["alive"]:
			continue
		if e["stun"] > 0:
			e["stun"] -= 1
			continue
		if e["recover"] > 0:
			e["recover"] -= 1
			continue
		if e["turn_window"] > 0:
			e["turn_window"] -= 1

		var to_p: Vector2 = player["pos"] - e["pos"]
		var dist: float = absf(to_p.x)
		var can_see: bool = _enemy_can_see_player(e)

		if e["type"] == "boss":
			_update_boss(e)
			continue

		if can_see:
			e["alert_pos"] = player["pos"]
			var desired_face: int = int(signf(to_p.x)) if absf(to_p.x) > 2.0 else int(e["facing"])
			if desired_face != e["facing"]:
				e["facing"] = desired_face
				if e["type"] == "shield":
					# Readable rear backstab window while shield guard pivots
					e["turn_window"] = 28

			if e["windup"] > 0:
				e["windup"] -= 1
				if e["windup"] == 0:
					_enemy_execute_attack(e)
					e["recover"] = 36
			else:
				if e["type"] == "melee" or e["type"] == "shield":
					if dist > 26.0:
						e["pos"].x += float(e["facing"]) * 68.0 * FIXED_DT
					else:
						e["windup"] = 22
						e["windup_max"] = 22
				elif e["type"] == "pistol":
					if dist < 240.0:
						e["aim_dir"] = (player["pos"] + Vector2(0, -12) - (e["pos"] + Vector2(0, -14))).normalized()
						e["windup"] = 28
						e["windup_max"] = 28
				elif e["type"] == "shotgun":
					if dist < 175.0:
						e["aim_dir"] = (player["pos"] + Vector2(0, -12) - (e["pos"] + Vector2(0, -14))).normalized()
						e["windup"] = 34
						e["windup_max"] = 34
		else:
			# Investigate sound/last known spot without omniscient tracking
			if e["alert_pos"].x >= 0.0:
				var dx: float = e["alert_pos"].x - e["pos"].x
				if absf(dx) > 8.0:
					e["facing"] = int(signf(dx))
					e["pos"].x += float(e["facing"]) * 52.0 * FIXED_DT
				else:
					e["alert_pos"] = Vector2(-1, -1)

func _update_boss(e: Dictionary) -> void:
	var to_p: Vector2 = player["pos"] - e["pos"]
	e["facing"] = int(signf(to_p.x)) if absf(to_p.x) > 2.0 else int(e["facing"])

	if e["windup"] > 0:
		e["windup"] -= 1
		if boss_signal == "RED":
			e["pos"].x += float(e["facing"]) * 145.0 * FIXED_DT
			if absf(player["pos"].x - e["pos"].x) < 18.0 and absf(player["pos"].y - e["pos"].y) < 20.0:
				if player["slash_timer"] == 0 and player["roll_timer"] == 0:
					_kill_player()
		elif e["windup"] == 0:
			if boss_signal == "YELLOW":
				# Teleport to telegraphed spot (never directly inside player's hitbox)
				e["pos"] = boss_telegraph_pos
				e["recover"] = 38
			elif boss_signal == "GREEN":
				for ang in [-0.14, 0.0, 0.14]:
					var d := Vector2(e["facing"], 0).rotated(ang)
					bullets.append({"pos": e["pos"] + Vector2(e["facing"] * 10, -14), "vel": d * 240.0, "owner": "enemy", "active": true})
				frame_events.append({"type": "sfx", "name": "shot", "pan": 0.0})
				e["recover"] = 42
		return

	boss_timer -= 1
	if boss_timer <= 0:
		if boss_signal == "RED":
			e["windup"] = 24
			e["windup_max"] = 24
			boss_timer = 75
		elif boss_signal == "YELLOW":
			# Choose safe offset behind/beside player with clear visual reflection
			var offset_x: float = -float(player["facing"]) * 56.0
			var tx: float = clampf(player["pos"].x + offset_x, 48.0, ROOM_W - 48.0)
			if absf(tx - player["pos"].x) < 36.0:
				tx = clampf(player["pos"].x + float(player["facing"]) * 64.0, 48.0, ROOM_W - 48.0)
			boss_telegraph_pos = Vector2(tx, FLOOR_Y)
			e["windup"] = 26
			e["windup_max"] = 26
			boss_timer = 80
		else:
			e["windup"] = 28
			e["windup_max"] = 28
			boss_timer = 85

func _enemy_execute_attack(e: Dictionary) -> void:
	if e["type"] == "melee" or e["type"] == "shield":
		if absf(player["pos"].x - e["pos"].x) <= 28.0 and absf(player["pos"].y - e["pos"].y) <= 22.0:
			if player["roll_timer"] == 0:
				_kill_player()
	elif e["type"] == "pistol":
		var muzzle: Vector2 = e["pos"] + Vector2(e["facing"] * 9, -14)
		bullets.append({"pos": muzzle, "vel": e["aim_dir"] * 280.0, "owner": "enemy", "active": true})
		frame_events.append({"type": "sfx", "name": "shot", "pan": clampf((e["pos"].x - player["pos"].x) / 220.0, -0.8, 0.8)})
	elif e["type"] == "shotgun":
		var muzzle: Vector2 = e["pos"] + Vector2(e["facing"] * 9, -14)
		for spread in [-0.16, -0.05, 0.05, 0.16]:
			bullets.append({"pos": muzzle, "vel": e["aim_dir"].rotated(spread) * 245.0, "owner": "enemy", "active": true})
		frame_events.append({"type": "sfx", "name": "shot", "pan": clampf((e["pos"].x - player["pos"].x) / 220.0, -0.8, 0.8), "pitch": 0.82})

func _update_hazards() -> void:
	# Smoke dissipation
	for s in smokes:
		if s["timer"] > 0:
			s["timer"] -= 1

	# Security cameras & cable power feed to turret (Wagon 4)
	for cam in cameras:
		cam["sweep"] = sin(world_time * 1.6) * 0.45
		var cone_dir := Vector2(cam["dir"], 0.65).normalized()
		var to_p: Vector2 = (player["pos"] + Vector2(0, -12)) - cam["pos"]
		if to_p.length() < 125.0 and to_p.normalized().dot(cone_dir) > 0.82 and not _segment_hits_wall(cam["pos"], player["pos"] + Vector2(0, -12)):
			cam["alert"] = 60
		elif cam["alert"] > 0:
			cam["alert"] -= 1

		if cam["alert"] > 0 and power_panel.get("active", false) and turret.get("alive", false):
			turret["cable_charge"] = minf(1.0, turret["cable_charge"] + 0.04)
			if turret["cable_charge"] >= 1.0:
				turret["powered"] = true

	if turret.get("powered", false) and turret.get("alive", false):
		turret["cooldown"] -= 1
		if turret["cooldown"] <= 0:
			turret["cooldown"] = 48
			var dir: Vector2 = ((player["pos"] + Vector2(0, -12)) - turret["pos"]).normalized()
			bullets.append({"pos": turret["pos"] + dir * 10.0, "vel": dir * 265.0, "owner": "enemy", "active": true})
			frame_events.append({"type": "sfx", "name": "shot", "pan": 0.2, "pitch": 1.18})

	# Chain-reaction barrels
	for b in barrels:
		if b["intact"] and b["fuse"] > 0:
			b["fuse"] -= 1
			if b["fuse"] == 0:
				_detonate_barrel(b)

func _detonate_barrel(b: Dictionary) -> void:
	if not b["intact"]:
		return
	b["intact"] = false
	shake_frames = 10
	shake_dir = Vector2.UP
	frame_events.append({"type": "sfx", "name": "explode", "pan": 0.0})
	clash_sparks.append({"pos": b["pos"], "timer": 18, "kind": "explode"})

	# Chain trigger nearby barrels
	for other in barrels:
		if other["intact"] and other["pos"].distance_to(b["pos"]) < 52.0:
			other["fuse"] = 10

	# Damage enemies & un-rolling player inside blast radius
	for e in enemies:
		if e["alive"] and e["pos"].distance_to(b["pos"]) < 54.0:
			_damage_enemy(e, (e["pos"] - b["pos"]).normalized())
	var invuln: bool = (player["roll_timer"] >= ROLL_IFRAME_START and player["roll_timer"] <= ROLL_IFRAME_END)
	if not invuln and player["pos"].distance_to(b["pos"]) < 46.0:
		_kill_player()

func _update_fx() -> void:
	if slash_fx.get("timer", 0) > 0:
		slash_fx["timer"] -= 1
	if shake_frames > 0:
		shake_frames -= 1
	for i in range(clash_sparks.size() - 1, -1, -1):
		clash_sparks[i]["timer"] -= 1
		if clash_sparks[i]["timer"] <= 0:
			clash_sparks.remove_at(i)

func _kill_player() -> void:
	if not player["alive"] or level_clear_delay > 0:
		return
	player["alive"] = false
	GameState.total_deaths += 1
	clear_buffered_commands()
	frame_events.append({"type": "sfx", "name": "hit", "pan": 0.0, "pitch": 0.72})
	mode = "DEAD_REWIND"
	replay_idx = recording.size() - 1

func _check_wagon_cleared() -> bool:
	# Wagon 3 stealth staff passage if player listened to Idil
	if wagon_id == 3 and GameState.radio_listened:
		if _player_rect(player["pos"]).intersects(alt_exit_zone):
			return true
	var any_alive := false
	for e in enemies:
		if e["alive"]:
			any_alive = true
			break
	if not any_alive and _player_rect(player["pos"]).intersects(exit_zone):
		return true
	return false

func _enemy_can_see_player(e: Dictionary) -> bool:
	var eye: Vector2 = e["pos"] + Vector2(0, -16)
	var target: Vector2 = player["pos"] + Vector2(0, -13)
	if absf(target.x - eye.x) > 255.0:
		return false
	# Closed doors block vision
	for d in doors:
		if not d["open"] and _segment_hits_rect(eye, target, Rect2(d["x"], d["y"], d["w"], d["h"])):
			return false
	# Solid walls/counters block vision
	if _segment_hits_wall(eye, target):
		return false
	# Active smoke clouds block vision
	for s in smokes:
		if s["timer"] > 0 and _segment_hits_circle(eye, target, s["pos"], s["radius"]):
			return false
	return true

func _alert_enemies_at(pos: Vector2) -> void:
	for e in enemies:
		if e["alive"] and e["pos"].distance_to(pos) < 160.0:
			e["alert_pos"] = pos

func _player_rect(p: Vector2) -> Rect2:
	if player.get("roll_timer", 0) > 0:
		return Rect2(p.x - 6.0, p.y - 14.0, 12.0, 14.0)
	return Rect2(p.x - 6.0, p.y - 24.0, 12.0, 24.0)

func _segment_hits_wall(a: Vector2, b: Vector2) -> bool:
	for w in walls:
		if _segment_hits_rect(a, b, w):
			return true
	return false

func _segment_wall_point(a: Vector2, b: Vector2):
	var best = null
	var best_d: float = 1e9
	for w in walls:
		var pt = _segment_rect_entry(a, b, w)
		if pt != null:
			var d: float = a.distance_to(pt)
			if d < best_d:
				best_d = d
				best = pt
	return best

func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	return _segment_rect_entry(a, b, r) != null

func _segment_rect_entry(a: Vector2, b: Vector2, r: Rect2):
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	var checks := [
		[-d.x, a.x - r.position.x],
		[d.x, r.end.x - a.x],
		[-d.y, a.y - r.position.y],
		[d.y, r.end.y - a.y],
	]
	for c in checks:
		var p: float = c[0]
		var q: float = c[1]
		if absf(p) < 1e-6:
			if q < 0.0:
				return null
		else:
			var t: float = q / p
			if p < 0.0:
				if t > t1:
					return null
				if t > t0:
					t0 = t
			else:
				if t < t0:
					return null
				if t < t1:
					t1 = t
	return a + d * t0

func _segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, rad: float) -> bool:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 1e-5:
		return a.distance_to(c) <= rad
	var t: float = clampf((c - a).dot(ab) / len_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(c) <= rad

func _record_snapshot(w_dt: float = FIXED_DT) -> void:
	recording.append({
		"world_dt": w_dt,
		"player": player.duplicate(true),
		"doors": doors.duplicate(true),
		"enemies": enemies.duplicate(true),
		"items": items.duplicate(true),
		"bullets": bullets.duplicate(true),
		"barrels": barrels.duplicate(true),
		"smokes": smokes.duplicate(true),
		"cameras": cameras.duplicate(true),
		"power_panel": power_panel.duplicate(true),
		"turret": turret.duplicate(true),
		"slash_fx": slash_fx.duplicate(true),
		"decal_count": blood_decals.size(),
		"camera_x": camera_x,
		"boss_signal": boss_signal,
		"boss_telegraph_pos": boss_telegraph_pos,
	})

func _apply_snapshot(snap: Dictionary) -> void:
	player = snap["player"].duplicate(true)
	doors = snap["doors"].duplicate(true)
	enemies = snap["enemies"].duplicate(true)
	items = snap["items"].duplicate(true)
	bullets = snap["bullets"].duplicate(true)
	barrels = snap["barrels"].duplicate(true)
	smokes = snap["smokes"].duplicate(true)
	cameras = snap["cameras"].duplicate(true)
	power_panel = snap["power_panel"].duplicate(true)
	turret = snap["turret"].duplicate(true)
	slash_fx = snap["slash_fx"].duplicate(true)
	camera_x = snap["camera_x"]
	boss_signal = snap["boss_signal"]
	boss_telegraph_pos = snap["boss_telegraph_pos"]
	var target_decals: int = snap["decal_count"]
	if blood_decals.size() > target_decals:
		blood_decals.resize(target_decals)
