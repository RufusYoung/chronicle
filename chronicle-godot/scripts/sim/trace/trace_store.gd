extends RefCounted
class_name V5TraceStore

var traces: Array = []


func add_trace(trace: Dictionary) -> void:
	var new_trace := trace.duplicate(true)
	var replacement_key := _replacement_key(new_trace)
	if replacement_key != "":
		for index in range(traces.size()):
			if _replacement_key(traces[index]) == replacement_key:
				traces[index] = new_trace
				return
	traces.append(new_trace)


func list_traces() -> Array:
	return traces.duplicate(true)


func list_traces_by_location(location_id: String) -> Array:
	var rows: Array = []
	for trace: Dictionary in traces:
		if str(trace.get("location_id", "")) == location_id:
			rows.append(trace.duplicate(true))
	return rows


func find_traces_by_type(trace_type: String) -> Array:
	var rows: Array = []
	for trace: Dictionary in traces:
		if str(trace.get("trace_type", "")) == trace_type:
			rows.append(trace.duplicate(true))
	return rows


func find_traces_by_source_fact(fact_type: String) -> Array:
	var rows: Array = []
	for trace: Dictionary in traces:
		if str(trace.get("source_fact_type", "")) == fact_type:
			rows.append(trace.duplicate(true))
	return rows


func _replacement_key(trace: Dictionary) -> String:
	var trace_type := str(trace.get("trace_type", ""))
	var actor_id := str(trace.get("actor_id", ""))
	var location_id := str(trace.get("location_id", ""))
	if trace_type == "" or actor_id == "" or location_id == "":
		return ""
	return "%s:%s:%s" % [trace_type, actor_id, location_id]
