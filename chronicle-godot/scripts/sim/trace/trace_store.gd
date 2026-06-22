extends RefCounted
class_name V5TraceStore

var traces: Array = []


func add_trace(trace: Dictionary) -> void:
	traces.append(trace.duplicate(true))


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
