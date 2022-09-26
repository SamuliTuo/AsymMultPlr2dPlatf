extends Area2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _on_Player1_OnAttack():
	monitoring = true
	print("started monitoring")
	yield(get_tree().create_timer(1.0), "timeout")
	monitoring = false
	print("STOPPED monitoring")
