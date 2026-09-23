extends "res://tests/sim/world_integration_contract_test.gd"


func run() -> void:
	var model := Live.new()
	var settings := options()
	settings.integration_rules_version = 2
	check(model.start(settings).success, "natural new-world adventure starts")
	var rounds := 0
	var transcript: Array = []
	for step: int in 100:
		var view: Dictionary = model.build_view_data()
		if int(model.session.get_time_summary().elapsed_hours) >= 72:
			break
		var actions: Array = model.session.PlayerLife.options(model.session)
		var result: Dictionary
		var selected := ""
		var combats: Array = model.session.get_combat_encounter_options()
		if not combats.is_empty():
			var approach: String = ["attack", "guard", "attack", "guard", "withdraw"][rounds % 5]
			var choice: Dictionary = combats.filter(func(row: Dictionary) -> bool: return row.approach_id == approach)[0]
			selected = str(choice.option_id)
			result = model.perform_combat_encounter(selected)
			rounds += 1
		else:
			var choice := _pick(actions, "eat") if view.player.hunger in ["high", "extreme"] else {}
			if choice.is_empty() and view.player.travel_remaining > 0:
				choice = _pick(actions, "continue")
			if choice.is_empty() and int(view.player.fatigue) >= 6:
				choice = _pick(actions, "rest")
			if choice.is_empty() and int(view.player.food_count) < 3:
				choice = _pick(actions, "gather:")
			if not choice.is_empty():
				selected = str(choice.action_id)
				result = model.act_player_life(selected)
			elif not str(view.location.id).ends_with(".terraces"):
				var routes: Array = model.session.get_travel_options()
				var route: Dictionary = {}
				for fragment: String in ["commons_to_terrace_farming", ".network.", "to_commons"]:
					var matches: Array = routes.filter(func(row: Dictionary) -> bool: return row.can_travel and fragment in str(row.route_id))
					if not matches.is_empty():
						route = matches[0]
						break
				if not route.is_empty():
					selected = str(route.route_id)
					result = model.perform_travel(selected)
			if selected == "":
				selected = "rest"
				result = model.act_player_life("rest")
		transcript.append({"time": view.time, "selected": selected, "result": result})
		if not result.get("success", false):
			check(false, "legal action failed: " + JSON.stringify(transcript.back()))
			break
	var journal: Dictionary = model.session.PlayerLife.Equipment.journal(model.session)
	var active: Array = journal.features.filter(func(row: Dictionary) -> bool:
		return row.get("xp", 0) > 0 or row.get("acquired", false))
	print("ADVENTURE_GROWTH " + JSON.stringify({"rounds": rounds, "active": active, "time": model.session.get_time_summary()}))
	check(rounds > 0, "formal journey meets live danger without injection")
	for id: String in ["skill.coast_survival", "skill.coast_melee", "skill.coast_guard", "trait.measured_retreat", "trait.patient_defender", "trait.battle_scar_caution"]:
		check(active.any(func(row: Dictionary) -> bool: return row.id == id), "legal experience creates " + id)
	var snapshot: Variant = model.session.PlayerLife.snapshot(model.session.context, model.session.stores, model.session.get_time_summary())
	var danger: Variant = model.session.WorldDanger.new()
	var encounter: Dictionary = danger.definition(snapshot, "player", snapshot.get_entity("world_threat.field_boar"), model.session.fixture_source_data.world_danger)
	var resolver: Variant = model.session.WorldDanger.Combat.new()
	resolver.configure(model.session.registry)
	var expected := {"attack": ["melee_attack", "patient_attack", "scar_attack"], "guard": ["guard_bonus", "patient_guard"],
		"withdraw": ["survival_escape", "retreat_learned", "scar_escape"]}
	for approach: String in expected:
		var preview: Dictionary = resolver.preview(encounter, snapshot, approach, "player")
		for modifier: String in expected[approach]:
			check(preview.modifier_evaluations.any(func(row: Dictionary) -> bool:
				return row.modifier_id == modifier and row.applied), "actual experience is consumed by combat: " + modifier)
	var path := "user://tests/adventure_growth/legal.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(model.save_to_path(path, true).success, "save actual injury, experiences and growth")
	var restored := Live.new()
	check(restored.load_from_path(path).success, "restore experienced actor")
	check(journal == restored.session.PlayerLife.Equipment.journal(restored.session), "growth and injuries persist exactly")
	var file := FileAccess.open(path.get_base_dir() + "/legal_actions.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"evidence_kind": "legal_developer_policy", "test_injection": false, "human_play": false,
		"transcript": transcript, "journal": journal, "checks": checks, "failures": failures}, "\t"))
	print("WORLD_ADVENTURE_GROWTH %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _pick(rows: Array, prefix: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.get("can_execute", false) and str(row.get("wrapped_action_id", row.action_id)).begins_with(prefix):
			return row
	return {}
