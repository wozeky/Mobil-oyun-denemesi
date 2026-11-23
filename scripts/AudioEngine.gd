extends Node

var sfx_streams: Dictionary = {}
var sfx_pool: Array[AudioStreamPlayer] = []
var pool_idx: int = 0

var mus_rail: AudioStreamPlayer
var mus_metal: AudioStreamPlayer
var mus_loco: AudioStreamPlayer

var target_cutoff: float = 20500.0
var current_cutoff: float = 20500.0
var target_pitch: float = 1.0
var current_pitch: float = 1.0

func _ready() -> void:
	var sfx_names := [
		"whiff", "hit", "block", "clash", "deflect",
		"shot", "door", "pickup", "radio", "footstep", "explode"
	]
	for n in sfx_names:
		var path := "res://assets/audio/sfx_%s.wav" % n
		if ResourceLoader.exists(path):
			sfx_streams[n] = load(path)

	for i in range(12):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_pool.append(p)

	mus_rail = _make_music_player("res://assets/audio/mus_rail_bass.wav")
	mus_metal = _make_music_player("res://assets/audio/mus_metal_perc.wav")
	mus_loco = _make_music_player("res://assets/audio/mus_loco_pulse.wav")
	start_music()

func _make_music_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	if ResourceLoader.exists(path):
		var st = load(path)
		if st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(3.2 * st.mix_rate)
		p.stream = st
	add_child(p)
	return p

func start_music() -> void:
	# Music measures never restart on death or rewind
	if mus_rail and not mus_rail.playing:
		mus_rail.play()
	if mus_metal and not mus_metal.playing:
		mus_metal.play()
	if mus_loco and not mus_loco.playing:
		mus_loco.play()

func update_mix(wagon: int, armed_visible: bool, focus_active: bool, is_replay: bool, is_rewinding: bool, muted: bool, delta: float) -> void:
	AudioServer.set_bus_mute(0, muted)

	# Layer levels by wagon progression & threat visibility
	if mus_rail:
		mus_rail.volume_db = -4.0
	if mus_metal:
		var metal_db := -5.0 if (armed_visible or wagon >= 2) else -45.0
		mus_metal.volume_db = lerpf(mus_metal.volume_db, metal_db, minf(1.0, delta * 6.0))
	if mus_loco:
		var loco_db := -6.0 if wagon >= 4 else (-16.0 if wagon == 3 else -50.0)
		mus_loco.volume_db = lerpf(mus_loco.volume_db, loco_db, minf(1.0, delta * 4.0))

	# Smooth low-pass filter and pitch shift in Focus or Death Rewind
	if is_rewinding:
		target_cutoff = 1100.0
		target_pitch = 0.84
	elif focus_active:
		target_cutoff = 920.0
		target_pitch = 0.78
	else:
		target_cutoff = 20500.0
		target_pitch = 1.0

	current_cutoff = lerpf(current_cutoff, target_cutoff, minf(1.0, delta * 10.0))
	current_pitch = lerpf(current_pitch, target_pitch, minf(1.0, delta * 10.0))

	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0 and AudioServer.get_bus_effect_count(music_bus) > 0:
		var fx = AudioServer.get_bus_effect(music_bus, 0)
		if fx is AudioEffectLowPassFilter:
			fx.cutoff_hz = current_cutoff

	for mp in [mus_rail, mus_metal, mus_loco]:
		if mp:
			mp.pitch_scale = current_pitch

	# Narrow-band CCTV speaker tone on SFX during success replay
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0 and AudioServer.get_bus_effect_count(sfx_bus) > 0:
		AudioServer.set_bus_effect_enabled(sfx_bus, 0, is_replay)

func play_sfx(name: String, pan: float = 0.0, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not sfx_streams.has(name):
		return
	var p := sfx_pool[pool_idx]
	pool_idx = (pool_idx + 1) % sfx_pool.size()
	p.stream = sfx_streams[name]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()
