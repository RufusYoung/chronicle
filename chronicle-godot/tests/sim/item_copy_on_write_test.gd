extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot.gd")
const Writer = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var model := Live.new()
	_check(model.start({"challenge_seed_override": 81001}).success, "fixture starts")
	var stores: Dictionary = model.session.stores
	var source: Variant = stores.item_store
	stores.fact_store.add_fact({"fact_id": "cow.test", "fact_type": "test", "tick": 1})
	_check(source.create_item({"item_instance_id": "cow.food", "item_def_id": "item.travel_ration",
		"quantity": 10, "holder": {"kind": "entity", "id": "player"}}, ["cow.test"]), "test food created")
	_check(source.create_item({"item_instance_id": "cow.cloak", "item_def_id": "item.waxed_winter_cloak",
		"quantity": 1, "holder": {"kind": "entity", "id": "player"}}, ["cow.test"]), "test equipment created")
	var original: Dictionary = source.items["cow.food"]
	_check(original.is_read_only() and original.holder.is_read_only() and original.history.is_read_only(),
		"canonical item record is recursively frozen")
	var writer := Writer.new()
	var preview: Dictionary = writer._build_preview_stores(stores).stores
	_check(is_same(preview.item_store.items["cow.food"], original), "preview shares unchanged item identity")
	_check(preview.item_store.entity_store == preview.entity_store and preview.item_store.fact_store == preview.fact_store,
		"preview uses preview validation dependencies")
	var snapshot: Variant = model.session.get_snapshot()
	var held: Dictionary = snapshot.get_item("cow.food")
	held.holder.id = "changed"
	held.history.append({"test": true})
	_check(snapshot.get_item("cow.food").holder.id == "player" and snapshot.get_item("cow.food").history.is_empty(),
		"snapshot getters remain independent and editable")
	var operations := [
		{"operation": "append_history", "item_instance_id": "cow.food", "history_entry": {"fact_id": "cow.test", "nested": {"v": [1]}}},
		{"operation": "transfer", "item_instance_id": "cow.food", "new_holder": {"kind": "entity", "id": "chen_mi"}},
		{"operation": "consume", "item_instance_id": "cow.food", "quantity": 1},
		{"operation": "increase_quantity", "item_instance_id": "cow.food", "quantity": 1},
		{"operation": "split_stack", "item_instance_id": "cow.food", "new_item_instance_id": "cow.split", "quantity": 2},
		{"operation": "adjust_durability", "item_instance_id": "cow.cloak", "delta": -1},
	]
	for change: Dictionary in operations:
		change["source_fact_ids"] = ["cow.test"]
		var item_id := str(change.item_instance_id)
		var previous: Dictionary = preview.item_store.items[item_id]
		var before := JSON.stringify(previous, "", true, true)
		_check(preview.item_store.apply_item_change(change), "preview applies " + str(change.operation))
		_check(JSON.stringify(previous, "", true, true) == before and not is_same(previous, preview.item_store.items[item_id]),
			str(change.operation) + " replaces record without editing previous revision")
	_check(source.get_item("cow.food").quantity == 10 and source.get_item("cow.food").holder.id == "player"
		and not source.items.has("cow.split"), "all preview operations leave live items unchanged")
	writer._commit_preview(preview, stores)
	preview.item_store.clear()
	_check(source.get_item("cow.food").quantity == 8 and source.get_item("cow.split").quantity == 2,
		"committed containers outlive the preview")
	_check(snapshot.get_item("cow.food").quantity == 10 and snapshot.get_item("cow.food").history.is_empty(),
		"old snapshot retains quantity, holder and history after commit")
	for copy: Dictionary in [source.get_item("cow.food"), source.list_item_records().filter(
			func(row: Dictionary) -> bool: return row.item_instance_id == "cow.food")[0]]:
		_check(not copy.holder.is_read_only() and not copy.history.is_read_only(), "public item copies are editable")
		copy.history.clear()
	_check(not source.get_item("cow.food").history.is_empty(), "public history edits cannot alter item history")
	var direct_input := {"item_id": "direct", "holder": {"id": "a"}}
	var direct := Snapshot.new({"items": [direct_input]})
	direct_input.holder.id = "b"
	_check(direct.get_item("direct").holder.id == "a", "direct snapshot constructor isolates mutable data")
	var first := Result.new()
	first.add_item_change({"operation": "consume", "item_instance_id": "cow.food", "quantity": 1, "source_fact_ids": ["cow.test"]})
	var invalid := Result.new()
	invalid.add_item_change({"operation": "consume", "item_instance_id": "cow.food", "quantity": 999, "source_fact_ids": ["cow.test"]})
	var before := JSON.stringify(source.to_save_data(), "", true, true)
	_check(not writer.apply_results([first, invalid], stores), "later invalid operation rejects batch")
	_check(JSON.stringify(source.to_save_data(), "", true, true) == before, "rollback retains items and complete history")
	var saved: Array = source.to_save_data()
	_check(source.load_save_data(saved).ok, "native item records reload")
	_check(source.items["cow.food"].history[0].is_read_only(), "reload freezes nested history")
	_check(JSON.stringify(source.to_save_data(), "", true, true) == before, "native representation remains exact")
	print("ITEM_COW_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
