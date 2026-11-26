extends RefCounted

## Unit checks of the heads-up display.
##
## The display shows the state of the character and sends the requests of the
## player, so it has to build every widget and keep the bars in step with the
## state of the server.

const HudControllerType: GDScript = preload("res://client/scripts/hud_controller.gd")
const EntityVisualEffectsType: GDScript = preload("res://client/scripts/entity_visual_effects.gd")


func run() -> bool:
	var hud: Control = HudControllerType.new()
	Engine.get_main_loop().root.add_child(hud)
	hud.setup(_build_config(), _build_registry())

	var unit_frame: PanelContainer = hud.get_node_or_null("UnitFrame")
	if not _check(unit_frame != null, "the frame of the character must exist"):
		return false
	var target_frame: PanelContainer = hud.get_node_or_null("TargetFrame")
	if not _check(target_frame != null, "the frame of the target must exist"):
		return false
	var action_bar: PanelContainer = hud.get_node_or_null("ActionBar")
	if not _check(action_bar != null, "the action bar must exist"):
		return false
	var experience_bar: ProgressBar = hud.get_node_or_null("ExperienceBar")
	if not _check(experience_bar != null, "the experience bar must exist"):
		return false
	var quick_bar: HBoxContainer = hud.get_node_or_null("QuickAccessBar")
	if not _check(quick_bar != null, "the quick access must exist"):
		return false
	if not _check(quick_bar.get_child_count() == 4, "the quick access needs four buttons"):
		return false

	var slots_root: HBoxContainer = action_bar.get_node("ActionBarRoot")
	if not _check(slots_root.get_child_count() == 8, "the action bar needs eight slots"):
		return false
	for index: int in range(HudControllerType.ABILITY_SLOT_COUNT):
		var slot: VBoxContainer = slots_root.get_child(index)
		var button: Button = slot.get_node("ActionButton")
		if not _check(not button.disabled, "the ability %d must be ready" % index):
			return false
		if not _check(
				slot.get_node("ActionButton/CooldownOverlay") is ColorRect,
				"the slot %d needs a cooldown overlay" % index,
		):
			return false

	hud.update_unit_frame(3, 80.0, 120.0, 25.0, 60.0, 175)
	var health_bar: ProgressBar = unit_frame.get_node("UnitFrameRoot/HealthRow/HealthBar")
	if not _check(is_equal_approx(health_bar.value, 80.0), "the health bar must show the health"):
		return false
	var health_value: Label = unit_frame.get_node("UnitFrameRoot/HealthRow/HealthValue")
	if not _check(health_value.text == "80 / 120", "the health must be readable"):
		return false
	var gold_label: Label = unit_frame.get_node("UnitFrameRoot/GoldLabel")
	if not _check(gold_label.text.contains("175"), "the gold must be readable"):
		return false

	if not _check(
			is_equal_approx(target_frame.modulate.a, 0.0),
			"the frame of the target starts hidden",
	):
		return false
	hud.update_target("enemy", "Training Slime", 2, 30.0, 30.0)
	if not _check(
			is_equal_approx(target_frame.modulate.a, 1.0),
			"the frame of the target must appear",
	):
		return false
	hud.hide_target()
	if not _check(
			is_equal_approx(target_frame.modulate.a, 0.0),
			"the frame of the target must hide",
	):
		return false

	hud.update_experience(40, 1)
	if not _check(experience_bar.value >= 0.0, "the experience bar must follow the state"):
		return false

	hud.update_quick_items(["minor_potion"])
	var item_slot: VBoxContainer = slots_root.get_child(HudControllerType.ABILITY_SLOT_COUNT)
	var item_button: Button = item_slot.get_node("ActionButton")
	if not _check(not item_button.disabled, "the quick item must be ready"):
		return false
	hud.update_quick_items([])
	if not _check(item_button.disabled, "an empty slot must be closed"):
		return false

	var requested: Array[String] = []
	hud.ability_requested.connect(func(ability_id: String) -> void: requested.append(ability_id))
	hud.ability_requested.emit("starter_slash")
	if not _check(requested.size() == 1, "the action bar must send the request"):
		return false

	hud.start_cooldown("starter_slash")
	var overlay: ColorRect = slots_root.get_child(0).get_node("ActionButton/CooldownOverlay")
	if not _check(overlay.visible, "the cooldown must be visible"):
		return false

	var ring: MeshInstance3D = EntityVisualEffectsType.create_target_ring(0.6, Color.RED)
	if not _check(ring.mesh is TorusMesh, "the ring must be a torus"):
		return false
	if not _check(ring.visible == false, "the ring starts hidden"):
		return false
	if not _check(
			EntityVisualEffectsType.target_color("enemy") != EntityVisualEffectsType.target_color("ally"),
			"the kinds of the target need different colors",
	):
		return false

	hud.free()
	ring.free()
	return true


## Builds a configuration for the display.
func _build_config() -> Dictionary:
	return {
		"inventory_slot_count": 20,
		"starting_gold": 100,
	}


## Builds a registry with the abilities of the action bar.
func _build_registry() -> Dictionary:
	var abilities: Dictionary = {}
	for ability_id: String in HudControllerType.ABILITY_IDS:
		abilities[ability_id] = {
			"name_key": "ability_%s" % ability_id,
			"cooldown_seconds": 1.0,
		}
	return {
		"abilities": abilities,
		"items": {
			"minor_potion": {
				"name_key": "item_minor_potion",
				"item_type": "consumable",
				"level_requirement": 1,
			},
		},
		"progression": {
			"level_1": {"experience_required": 0, "max_health": 100},
			"level_2": {"experience_required": 80, "max_health": 120},
		},
	}


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
