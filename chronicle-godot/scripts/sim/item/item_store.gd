extends RefCounted
class_name V5ItemStore

var items: Dictionary = {}


func load_initial_items(source_items: Array) -> void:
	items.clear()
	for item: Dictionary in source_items:
		_create_item(item)


func apply_item_change(change: Dictionary) -> void:
	if str(change.get("operation", "")) != "create":
		return
	var item: Variant = change.get("item", {})
	if item is Dictionary:
		_create_item(item)


func get_item(item_id: String) -> Dictionary:
	if not items.has(item_id):
		return {}
	return (items[item_id] as Dictionary).duplicate(true)


func list_items() -> Array:
	var rows: Array = []
	for item: Dictionary in items.values():
		rows.append(item.duplicate(true))
	return rows


func list_items_for_owner(owner_id: String) -> Array:
	var rows: Array = []
	for item: Dictionary in items.values():
		if str(item.get("owner_id", "")) == owner_id:
			rows.append(item.duplicate(true))
	return rows


func _create_item(item: Dictionary) -> void:
	var item_id := str(item.get("item_id", item.get("id", "")))
	if item_id == "" or items.has(item_id):
		return
	var stored_item := item.duplicate(true)
	stored_item["item_id"] = item_id
	items[item_id] = stored_item
