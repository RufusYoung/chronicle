extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var model := Live.new()
	_check(model.start({"scenario": "echo_realm", "challenge_seed_override": 81001}).success, "canon fixture starts")
	var store: Variant = model.session.stores.fact_store
	for row: Dictionary in [{"fact_id": "index.a", "fact_type": "test", "actor_id": "actor"},
			{"fact_id": "index.b", "fact_type": "other"}, {"fact_id": "index.c", "fact_type": "test"},
			{"fact_id": "index.legacy", "type": "test"}, {"fact_id": "index.blank", "fact_type": ""}]:
		store.add_fact(row)
	var indexed: Variant = model.session.get_snapshot()
	var direct := Snapshot.new(indexed.to_dict())
	_check(indexed.facts.is_read_only() and not direct.facts.is_read_only(),
		"formal indexed history is immutable; direct test snapshots remain editable")
	var detached: Array = indexed.get_facts()
	detached.clear()
	_check(not indexed.get_facts_by_type("test").is_empty() and not indexed.get_facts().is_empty(),
		"editing a facts query cannot invalidate the formal index")
	for actor: String in ["actor", "", "missing"]:
		_check(JSON.stringify(indexed.get_facts_by_actor(actor), "", true, true)
			== JSON.stringify(direct.get_facts_by_actor(actor), "", true, true), "actor index preserves order: " + actor)
	for kind: String in ["test", "other", "", "missing", "settlement_generated"]:
		_check(JSON.stringify(indexed.get_facts_by_type(kind), "", true, true)
			== JSON.stringify(direct.get_facts_by_type(kind), "", true, true),
			"index preserves exact fact_type and original order: " + kind)
	var rows: Array = indexed.get_facts_by_type("test")
	_check(rows.size() == 2 and rows[0].fact_id == "index.a" and rows[1].fact_id == "index.c",
		"legacy type alias is not mistaken for canonical fact_type")
	_check(rows[0].is_read_only(), "indexed rows remain immutable")
	rows.clear()
	_check(indexed.get_facts_by_type("test").size() == 2, "query result array is detached")
	store.add_fact({"fact_id": "index.new", "fact_type": "test"})
	_check(indexed.get_facts_by_type("test").size() == 2
		and model.session.get_snapshot().get_facts_by_type("test").size() == 3, "later append cannot enter old index")
	store.load_save_data([])
	_check(indexed.get_facts_by_type("test").size() == 2, "store replacement cannot clear old snapshot")
	_check(indexed.get_facts_by_actor("actor").size() == 1, "store replacement cannot clear old actor index")
	direct.facts.append({"fact_id": "direct", "fact_type": "mutable"})
	_check(direct.get_facts_by_type("mutable").size() == 1, "mutable fixture does not use stale cached index")
	_check(model.session.get_world_log_entry_count() == model.session.get_world_log_entries().size(),
		"log count equals materialized history size")
	print("SNAPSHOT_FACT_INDEX_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
