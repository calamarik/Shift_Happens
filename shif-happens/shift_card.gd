@tool
class_name ShiftCard
extends Node2D
## A draggable 8h shift card representing one employee.
## Open shift_card.tscn to restyle every card at once (frame, portrait, label...).
## Two kinds exist:
##  - tray card (is_tray = true): the stack in the tray, shows how many shifts are left.
#$Sprite##  - placed card: a copy spawned from a tray card, lives on the schedule.

const ANIMAL_DIR := "res://assets/animals/"
const PORTRAIT_H := 18.0
const NAME_TOP := 22.0

@export var employee_name := "Name":
	set(v):
		employee_name = v
		_apply()
@export var species := "bunny":   # file name in assets/animals (without .png)
	set(v):
		species = v
		_apply()
@export var color := Color.WHITE:  # tint of the card frame
	set(v):
		color = v
		_apply()
@export var card_size := Vector2(18, 76):
	set(v):
		card_size = v
		_apply()
@export var is_tray := false:
	set(v):
		is_tray = v
		_apply()
@export var remaining := 0:       # tray cards only: shifts still available this week
	set(v):
		remaining = v
		_apply()

var slot := Vector2i(-1, -1)   # (day, first period) once placed, (-1,-1) otherwise
var lane := -1                 # which lane inside the day column (0 = leftmost)
var source: ShiftCard = null   # placed card -> the tray card it came from

@onready var frame: NinePatchRect = $Frame
@onready var portrait: ColorRect = $Portrait
@onready var sprite: Sprite2D = $Sprite
@onready var name_label: Label = $NameLabel
@onready var count_label: Label = $CountLabel


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	frame.size = card_size
	frame.self_modulate = color
	portrait.position = Vector2(1, 1)
	portrait.size = Vector2(card_size.x - 2.0, PORTRAIT_H)

	var path := ANIMAL_DIR + species + ".png"
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	sprite.position = Vector2(floorf((card_size.x - 16.0) * 0.5), 2)

	# Name is written vertically so it fits however narrow the lane is.
	var reserved := 17.0 if is_tray else 3.0
	var length := maxf(card_size.y - NAME_TOP - reserved, 8.0)
	name_label.text = employee_name
	name_label.size = Vector2(length, 16)
	name_label.rotation = -PI / 2.0
	name_label.position = Vector2(card_size.x * 0.5 - 8.0, NAME_TOP + length)

	count_label.visible = is_tray
	count_label.text = "x%d" % remaining
	count_label.size = Vector2(card_size.x, 16)
	count_label.position = Vector2(0, card_size.y - 17.0)

	modulate.a = 1.0 if (not is_tray or remaining > 0) else 0.35


func get_rect_global() -> Rect2:
	return Rect2(global_position, card_size)
