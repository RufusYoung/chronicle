extends RefCounted
## Cosmetic selection never reads or advances simulation RNG.

const ATLAS = preload("res://art/characters/lakeside_residents_pixel_v1.png")


static func cell(entity_id: String, age: int) -> int:
	if not entity_id.begins_with("generated_resident.") or age < 0:
		return -1
	var variant := 0
	for index: int in entity_id.length():
		variant = (variant * 31 + entity_id.unicode_at(index)) % 4
	return (0 if age < 18 else (2 if age >= 65 else 1)) * 4 + variant


static func portrait(entity_id: String, age: int) -> Texture2D:
	var index := cell(entity_id, age)
	if index < 0:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	var cell_size := Vector2(ATLAS.get_width() / 4.0, ATLAS.get_height() / 3.0)
	texture.region = Rect2(Vector2(index % 4, int(index / 4)) * cell_size, cell_size)
	return texture
