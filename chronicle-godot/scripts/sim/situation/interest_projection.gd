extends RefCounted
## Questions derive from learned facts. A local observation is knowledge, not a quest outcome.

const Continuity = preload("res://scripts/sim/situation/situation_continuity.gd")
const Intents = preload("res://scripts/sim/situation/equipment_intents.gd")
const Brief = preload("res://scripts/sim/player/brief_actions.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")


static func local_evidence(session: Variant, snapshot: Variant) -> Dictionary:
	var location := str(session.context.location_id)
	var now := Intents.now(snapshot.world_time)
	var evidence := {"location_id": location, "observed_hour": now, "minute": snapshot.world_time.get("minute", 0),
		"threats": [], "traces": [], "people": []}
	for entity: Dictionary in snapshot.get_entities_by_type("creature"):
		if entity.states.get("location_id") == location and entity.states.get("visible", false) \
			and session.WorldDanger.active(entity, snapshot.world_time, session.fixture_source_data.get("world_danger", {})):
			evidence.threats.append({"id": entity.id, "name": entity.display_name})
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if Intents.present(person, location) and person.states.get("visible", false):
			evidence.people.append(person.id)
	for trace: Dictionary in session.stores.trace_store.list_traces_by_location(location):
		if trace.get("trace_type") != "equipment_activity" or not trace.get("visible", false) \
			or now >= int(trace.get("expires_hour", 0)) or int(trace.get("created_hour", now + 1)) > now \
			or trace.get("witness_id", session.context.actor_id) != session.context.actor_id:
			continue
		var source: Dictionary = snapshot.get_fact(str(trace.get("source_fact_id", "")))
		if source.is_empty() or source.get("location_id") != location or source.get("actor_id") != trace.get("actor_id"):
			continue
		evidence.traces.append({"where": location, "when": trace.created_hour, "source": source.fact_id,
			"subject": trace.actor_id, "what_changed": source.fact_type, "visibility": "local_public" if not trace.has("witness_id") else "own_witness",
			"decay": {"expires_hour": trace.expires_hour}, "provenance": "native_trace_store",
			"text": trace.get("description", "")})
	return evidence


static func record_observation(session: Variant) -> bool:
	if not Continuity.enabled(session):
		return true
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	if snapshot.player.get("daily_route_id", "") != "":
		return true
	var evidence := local_evidence(session, snapshot)
	var actor := str(session.context.actor_id)
	var facts: Array = snapshot.get_facts_by_actor(actor)
	if not facts.is_empty() and facts.back().get("fact_type") == "situation_place_observed" and facts.back().get("evidence") == evidence:
		return true
	var sources: Array = evidence.traces.map(func(t: Dictionary) -> String: return str(t.source))
	var result := Result.new()
	result.add_fact({"fact_id": "fact.interest_observation.%s.%d" % [Brief.stamp(session), facts.size()],
		"fact_type": "situation_place_observed", "actor_id": actor, "location_id": session.context.location_id,
		"day": snapshot.world_time.day, "hour": snapshot.world_time.hour, "minute": evidence.minute,
		"source_fact_ids": sources, "evidence": evidence})
	result.mark_resolved("player_local_observation")
	return session.writer.apply_result(result, session.stores)


static func build(session: Variant, snapshot: Variant) -> Array:
	var rows: Array = []
	var facts: Array = snapshot.get_facts_by_actor(str(session.context.actor_id))
	for known: Dictionary in Continuity.knowledge(session, snapshot):
		if known.kind != "danger":
			continue
		var source: Dictionary = snapshot.get_fact(str(known.source_fact_id))
		var title := "确认%s提过的危险是否还在" % known.name
		var row := {"id": "visit:" + str(known.location_id), "subject": known.subject_id,
			"known_fact": str(source.get("statement", source.get("summary", ""))), "source": known.source_fact_id,
			"age": known.age_hours, "relevance": "danger", "possible_value": "确认当前通行风险，不保证遭遇或报酬",
			"why_care": "%s提过在%s遇险。" % [known.name, known.place],
			"title": title, "uncertainty": "那里的威胁现在是否仍在？", "cost_hint": "道路与准备占用真实时间，旧消息可能失效",
			"provenance": "learned_testimony", "question_status": "stale" if known.stale else "open",
			"resolution_type": "", "answer": "", "new_information_count": 0, "evidence": []}
		var observed := {}
		var source_seen := false
		for fact: Dictionary in facts:
			if fact.get("fact_id") == source.fact_id:
				source_seen = true
			elif source_seen and fact.get("fact_type") == "situation_place_observed" and fact.get("location_id") == known.location_id:
				observed = fact.evidence.duplicate(true)
				observed["source_fact_id"] = fact.fact_id
		if session.context.location_id == known.location_id and snapshot.player.get("daily_route_id", "") == "":
			observed = local_evidence(session, snapshot)
			observed["source_fact_id"] = "current_local_observation"
		if not observed.is_empty():
			resolve_place(row, observed, source, session.context.location_id == known.location_id)
		rows.append(row)
	# A gift creates personal involvement, but the recipient's later life remains unknown until heard.
	for fact: Dictionary in facts:
		if fact.get("fact_type") != "equipment_given":
			continue
		var subject := str(fact.get("target_id", ""))
		if subject == "":
			continue
		var name := str(snapshot.get_entity(subject).get("display_name", "受赠者"))
		var row := {"id": "followup:" + subject, "subject": subject, "known_fact": fact.summary, "source": fact.fact_id,
			"age": maxi(Intents.now(snapshot.world_time) - Intents.now(fact), 0), "relevance": "relationship",
			"possible_value": "了解交出的物品后来有何用途", "why_care": "你曾把自己的装备交给%s。" % name,
			"title": "问%s，交出的装备后来怎样了" % name, "uncertainty": "对方后来如何使用，事情有没有办成？",
			"cost_hint": "需要当面重逢；人不会原地等候", "provenance": "own_contribution",
			"question_status": "open", "resolution_type": "", "answer": "", "new_information_count": 0, "evidence": []}
		for update: Dictionary in facts:
			if update.get("fact_type") == "situation_heard_update" and update.get("contribution_id") == fact.fact_id:
				row.merge({"question_status": "resolved", "resolution_type": "AFTERMATH", "answer": update.summary,
					"new_information_count": 1, "evidence": [update.fact_id]}, true)
		rows = rows.filter(func(old: Dictionary) -> bool: return old.id != row.id)
		rows.append(row)
	return rows


static func resolve_place(row: Dictionary, observed: Dictionary, source: Dictionary, here: bool) -> void:
	row["evidence"] = [observed.source_fact_id]
	row["observed_hour"] = observed.observed_hour
	row.question_status = "resolved"
	row.new_information_count = 1
	var prefix := "眼下" if here else "你上次到场时"
	var finding_person: bool = row.get("relevance") == "person"
	if finding_person and row.subject in observed.get("people", []):
		row.resolution_type = "ACTIVE_SITUATION"
		row.answer = prefix + "见到了%s，可以当面交谈；旧消息中的去向已得到核实。" % row.name
		return
	if not finding_person and not observed.threats.is_empty():
		row.resolution_type = "ACTIVE_SITUATION"
		row.answer = prefix + "确实看见了%s；是否应对由你决定。" % str(observed.threats[0].name)
		if not here:
			row.answer += "这不是远处的实时消息。"
		return
	var traces: Array = observed.traces.filter(func(t: Dictionary) -> bool:
		return t.subject == row.subject and int(t.when) > Intents.now(source))
	row.resolution_type = "AFTERMATH" if not traces.is_empty() else "COLD_TRAIL"
	row.answer = prefix + ("没有见到%s。" % row.name if finding_person else "没有看见威胁。")
	if not traces.is_empty():
		var trace: Dictionary = traces.back()
		row.answer += "\n" + str(trace.text) + ("\n只能确认此人后来在这里活动，如今去向仍未知。" if finding_person else "\n这能确认此人后来在这里活动，不能证明危险被击退或去了别处。")
		row.evidence.append(trace.source)
		row.new_information_count += 1
	else:
		row.answer += "没有找到回答这条旧消息的新余波；这次追索可以到此为止，不必原地等它出现。"
	if not here:
		row.answer += "如今远处是否变化仍未知。"


static func arrival(session: Variant, selected: Dictionary) -> Dictionary:
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var subject := str(selected.subject_id)
	var source: Dictionary = snapshot.get_fact(str(selected.source_fact_id))
	var row := {"subject": subject, "name": snapshot.get_entity(subject).get("display_name", "要找的人"),
		"relevance": "danger" if selected.get("lead_kind") == "danger" else "person", "source": source.fact_id}
	var evidence := local_evidence(session, snapshot)
	evidence["source_fact_id"] = "current_local_observation"
	resolve_place(row, evidence, source, true)
	return row


static func validate(session: Variant, restored_hour: int) -> String:
	var now := restored_hour if restored_hour >= 0 else Intents.now(session.get_time_summary())
	for fact: Dictionary in session.stores.fact_store.list_facts():
		if fact.get("fact_type") != "situation_place_observed":
			continue
		var evidence: Variant = fact.get("evidence")
		if not evidence is Dictionary or evidence.get("location_id") != fact.get("location_id") \
			or not session.context.locations.has(str(fact.get("location_id", ""))) or fact.get("actor_id") != session.context.actor_id \
			or evidence.get("observed_hour") != Intents.now(fact) or Intents.now(fact) > now:
			return "interest_observation_invalid"
		for key: String in ["threats", "traces", "people"]:
			if not evidence.get(key) is Array:
				return "interest_observation_invalid"
		if not evidence.get("minute", 0) is float and not evidence.get("minute", 0) is int:
			return "interest_observation_invalid"
		if int(evidence.get("minute", 0)) not in range(0, 60):
			return "interest_observation_invalid"
		for threat: Variant in evidence.threats:
			if not threat is Dictionary or not threat.get("id") is String or not threat.get("name") is String \
				or session.stores.entity_store.get_entity(threat.id).get("type") != "creature":
				return "interest_observation_invalid"
		for person: Variant in evidence.people:
			if not person is String or not session.stores.entity_store.has_entity(person):
				return "interest_observation_invalid"
		for trace: Variant in evidence.traces:
			if not trace is Dictionary or not trace.get("source") is String or not trace.get("text") is String \
				or not trace.get("subject") is String or trace.get("where") != fact.location_id \
				or not trace.get("decay") is Dictionary or not (trace.get("when") is float or trace.get("when") is int) \
				or trace.source not in fact.get("source_fact_ids", []):
				return "interest_observation_source_invalid"
			var source: Dictionary = session.stores.fact_store.get_fact(trace.source)
			if source.get("location_id") != fact.location_id or source.get("actor_id") != trace.subject \
				or Intents.now(source) != int(trace.when) or int(trace.when) > Intents.now(fact) \
				or int(trace.decay.get("expires_hour", 0)) <= Intents.now(fact):
				return "interest_observation_source_invalid"
	return ""
