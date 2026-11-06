extends Node2D
## Shift Happens - prototype step 5: everything is a real node in main.tscn.
##
## The layout is READ FROM THE SCENE: move or resize the nodes in the editor and the logic follows.
##   - Board                  = origin of the grid
##   - Board/Cells/Cell_0_0   = top-left cell, Cell_1_0 gives the column width, Cell_0_1 the row height
##   - Tray/Tray_<name>       = one ShiftCard stack per employee
## Each day = 4 periods of 4h. A shift = 2 consecutive periods, so 3 shifts per day:
##   Morning (periods 0-1) 06-14h, Afternoon (1-2) 10-18h, Evening (2-3) 14-22h.
## Each day column has `max_lanes` lanes; shifts that overlap in time can't share a lane.
##
## Game resolution is 640x360 (shown at 2x). Pixels are chunky on purpose.

const SHIFT_CARD := preload("res://shift_card.tscn")
const COLS := 7
const ROWS := 4
const SHIFT_NAMES := ["Morning", "Afternoon", "Evening"]
const TEXT_COLOR := Color("5b4a6b")

@export var shifts_per_week := 5      # how many times each employee can be dragged out
@export var max_lanes := 4            # max cards side by side in one day
@export var pad := Vector2(2, 2)      # space between a card and its shift's border
@export var lane_line_color := Color("a894d6")   # dotted separators between lanes in each day

@onready var board: Node2D = $Board
@onready var overlay: Node2D = $Overlay
@onready var tray_root: Node2D = $Tray
@onready var cards_root: Node2D = $Cards

var origin := Vector2.ZERO
var col_w := 88.0
var row_h := 40.0
var lane_w := 22.0
var card_size := Vector2(18, 76)

var tray: Array[ShiftCard] = []     # one stack per employee
var cards: Array[ShiftCard] = []    # all spawned shift cards (placed or being dragged)
var dragged: ShiftCard = null
var drag_offset := Vector2.ZERO
var hover := Vector3i(-1, -1, -1)   # (day, first period, lane); x == -1 -> not over the grid; z == -1 -> column full


func _ready() -> void:
	_read_layout()
	overlay.draw.connect(_draw_overlay)
	overlay.queue_redraw()
	for child in tray_root.get_children():
		var t := child as ShiftCard
		if t == null:
			continue
		t.is_tray = true
		t.card_size = card_size
		t.remaining = shifts_per_week
		tray.append(t)


## Grid geometry comes from the cell nodes, so the scene is the single source of truth.
func _read_layout() -> void:
	var c00: Control = board.get_node("Cells/Cell_0_0")
	var c10: Control = board.get_node("Cells/Cell_1_0")
	var c01: Control = board.get_node("Cells/Cell_0_1")
	origin = c00.global_position
	col_w = c10.global_position.x - origin.x
	row_h = c01.global_position.y - origin.y
	lane_w = col_w / max_lanes
	card_size = Vector2(lane_w - pad.x * 2.0, row_h * 2.0 - pad.y * 2.0)


# ---------------------------------------------------------------- drawing
func _draw_overlay() -> void:
	var o := overlay
	var th := ThemeDB.get_project_theme()
	var font: Font = th.default_font if th != null and th.default_font != null else ThemeDB.fallback_font
	var font_size: int = th.default_font_size if th != null and th.default_font_size > 0 else 16

	# dotted lane separators inside every day (1px, pixel-aligned)
	var bottom := origin.y + ROWS * row_h - 3.0
	for d in COLS:
		for l in range(1, max_lanes):
			var x := floorf(origin.x + d * col_w + l * lane_w)
			var y := origin.y + 3.0
			while y < bottom:
				o.draw_rect(Rect2(x, y, 1, 2), lane_line_color)
				y += 4.0

	# snap preview while dragging
	if hover.x >= 0:
		var col_x := origin.x + hover.x * col_w
		var top_y := origin.y + hover.y * row_h
		var shift_rect := Rect2(col_x, top_y, col_w, row_h * 2.0)
		o.draw_rect(shift_rect, Color(1, 0.85, 0.3, 0.2))
		o.draw_string(font, Vector2(col_x, top_y + 13), SHIFT_NAMES[hover.y],
			HORIZONTAL_ALIGNMENT_CENTER, col_w, font_size, TEXT_COLOR)
		if hover.z >= 0:
			var lane_rect := Rect2(col_x + hover.z * lane_w, top_y, lane_w, row_h * 2.0)
			o.draw_rect(lane_rect, Color(0.45, 0.9, 0.65, 0.4))
			o.draw_rect(lane_rect, Color(0.25, 0.7, 0.5, 1.0), false, 1.0)
		else:
			o.draw_rect(shift_rect, Color(1, 0.4, 0.4, 0.3))
			o.draw_rect(shift_rect, Color(0.9, 0.25, 0.3, 1.0), false, 1.0)


# ---------------------------------------------------------------- helpers
func _card_origin(day: int, row: int, lane: int) -> Vector2:
	return origin + Vector2(day * col_w + lane * lane_w + pad.x, row * row_h + pad.y)


## True if another card already uses this lane on this day during any of the same periods.
func _lane_taken(day: int, row: int, lane: int, ignore: ShiftCard) -> bool:
	for c in cards:
		if c == ignore or c.slot.x != day or c.lane != lane:
			continue
		if c.slot.y < row + 2 and row < c.slot.y + 2:   # the two 2-period ranges overlap
			return true
	return false


## Where would this card land? Returns (day, first period, lane).
## x == -1: outside the grid. z == -1: no free lane in that shift (column full).
func _resolve(card: ShiftCard) -> Vector3i:
	var center := card.position + card.card_size * 0.5
	var local := center - origin
	if local.x < 0 or local.y < 0 or local.x >= COLS * col_w or local.y >= ROWS * row_h:
		return Vector3i(-1, -1, -1)
	var day := int(local.x / col_w)
	var row := clampi(roundi((card.position.y - origin.y - pad.y) / row_h), 0, ROWS - 2)
	# Preferred lane = the one under the card; if taken, nearest free lane.
	var wanted := clampi(int((local.x - day * col_w) / lane_w), 0, max_lanes - 1)
	for offset in max_lanes:
		for dir in [1, -1]:
			var l: int = wanted + offset * dir
			if l < 0 or l >= max_lanes:
				continue
			if not _lane_taken(day, row, l, card):
				return Vector3i(day, row, l)
	return Vector3i(day, row, -1)


func _snap_to(card: ShiftCard, target: Vector2) -> void:
	var tw := create_tween()
	tw.tween_property(card, "position", target.round(), 0.12).set_trans(Tween.TRANS_QUAD)


## Remove a spawned card: it flies back to its tray stack and the counter goes up.
func _send_back(card: ShiftCard) -> void:
	cards.erase(card)
	card.slot = Vector2i(-1, -1)
	card.lane = -1
	card.source.remaining += 1
	var tw := create_tween()
	tw.tween_property(card, "position", card.source.global_position, 0.12).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(card.queue_free)


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_pick(event.position)
		elif dragged:
			_drop()
	elif event is InputEventMouseMotion and dragged:
		dragged.position = (event.position - drag_offset).round()
		hover = _resolve(dragged)
		overlay.queue_redraw()


func _try_pick(mouse: Vector2) -> void:
	# 1) a card already on the schedule (topmost first)
	for i in range(cards.size() - 1, -1, -1):
		var c := cards[i]
		if c.get_rect_global().has_point(mouse):
			dragged = c
			drag_offset = mouse - c.position
			cards_root.move_child(c, cards_root.get_child_count() - 1)  # draw on top
			return
	# 2) a tray stack that still has shifts left -> spawn a copy
	for t in tray:
		if t.remaining > 0 and t.get_rect_global().has_point(mouse):
			var c: ShiftCard = SHIFT_CARD.instantiate()
			c.employee_name = t.employee_name
			c.species = t.species
			c.color = t.color
			c.card_size = t.card_size
			c.source = t
			c.position = t.global_position
			cards_root.add_child(c)
			cards.append(c)
			t.remaining -= 1
			dragged = c
			drag_offset = mouse - c.position
			return


func _drop() -> void:
	var target := _resolve(dragged)
	if target.x >= 0 and target.z >= 0:
		dragged.slot = Vector2i(target.x, target.y)
		dragged.lane = target.z
		_snap_to(dragged, _card_origin(target.x, target.y, target.z))
	elif target.x >= 0 and dragged.slot.x >= 0:
		# Shift is full: go back to where the card was before.
		_snap_to(dragged, _card_origin(dragged.slot.x, dragged.slot.y, dragged.lane))
	else:
		# Outside the grid (or full and never placed): back to the tray, counter +1.
		_send_back(dragged)
	dragged = null
	hover = Vector3i(-1, -1, -1)
	overlay.queue_redraw()
