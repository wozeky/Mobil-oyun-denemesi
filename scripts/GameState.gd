extends Node

var current_wagon := 1
var total_deaths := 0
var intro_played := false
var radio_started := false
var radio_finished := false
var radio_listened := false
var radio_interrupted := false
var found_shift_manifest := false
var muted := false

func reset_campaign() -> void:
	current_wagon = 1
	total_deaths = 0
	intro_played = false
	radio_started = false
	radio_finished = false
	radio_listened = false
	radio_interrupted = false
	found_shift_manifest = false
