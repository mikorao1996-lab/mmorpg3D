extends Node3D

@onready var status_label: Label = $StatusCanvas/StatusPanel/StatusLabel


func _ready() -> void:
	status_label.text = tr("bootstrap_ready")
	push_warning(tr("bootstrap_ready"))
