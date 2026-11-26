class_name HudController
extends Control

## The heads-up display of the client.
##
## The controller owns the frames of the modern MMO interface: the frame of the
## character with its bars, the frame of the current target, the action bar
## with the abilities and the quick items, the experience bar, and the quick
## access buttons. The controller only shows what the server reported; every
## action of the interface is a request.
##
## The names of the nodes and the signals of the existing panels stay as they
## are, so the interface can be restyled without touching the contracts of the
## tests.

signal ability_requested(ability_id: String)
signal item_use_requested(item_id: String)
signal quick_action_requested(action: String)

const ABILITY_SLOT_COUNT: int = 5
const ITEM_SLOT_COUNT: int = 3
const TOTAL_SLOT_COUNT: int = ABILITY_SLOT_COUNT + ITEM_SLOT_COUNT
const EntityVisualEffectsType: GDScript = preload("res://client/scripts/entity_visual_effects.gd")
const SLOT_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
const ABILITY_IDS: Array[String] = [
	"starter_slash",
	"heavy_strike",
	"guard_break",
	"whirlwind",
	"second_wind",
]
const HOTKEYS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8"]
const QUICK_ACTIONS: Array[String] = ["inventory", "skills", "journal", "party"]
const TARGET_FADE_SECONDS: float = 0.18

var _config: Dictionary = {}
var _registry: Dictionary = {}
var _unit_frame: PanelContainer = null
var _unit_name_label: Label = null
var _unit_level_badge: Label = null
var _health_bar: ProgressBar = null
var _health_value: Label = null
var _resource_bar: ProgressBar = null
var _resource_value: Label = null
var _gold_label: Label = null
var _target_frame: PanelContainer = null
var _target_name_label: Label = null
var _target_level_label: Label = null
var _target_health_bar: ProgressBar = null
var _action_bar: PanelContainer = null
var _slot_buttons: Array[Button] = []
var _slot_overlays: Array[ColorRect] = []
var _slot_item_ids: Array[String] = []
var _experience_bar: ProgressBar = null
var _quick_buttons: Dictionary = {}


## Builds the widgets and reads the registries of the game.
func setup(config: Dictionary, registry: Dictionary) -> void:
	_config = config
	_registry = registry
	_build_unit_frame()
	_build_target_frame()
	_build_action_bar()
	_build_experience_bar()
	_build_quick_access()


## Shows the state of the character in the frame of the unit.
func update_unit_frame(
	level: int,
	health: float,
	max_health: float,
	resource: float,
	max_resource: float,
	gold: int,
) -> void:
	if _unit_frame == null:
		return
	_unit_level_badge.text = tr("hud_level_badge") % level
	_health_bar.max_value = maxf(max_health, 1.0)
	_health_bar.value = clampf(health, 0.0, maxf(max_health, 1.0))
	_health_value.text = "%d / %d" % [int(health), int(max_health)]
	_resource_bar.max_value = maxf(max_resource, 1.0)
	_resource_bar.value = clampf(resource, 0.0, maxf(max_resource, 1.0))
	_resource_value.text = "%d / %d" % [int(resource), int(max_resource)]
	_gold_label.text = tr("hud_gold") % gold


## Shows the entity the player aims at.
##
## The frame fades in and out, so it never jumps over the world.
func update_target(
	kind: String,
	display_name: String,
	level: int,
	health: float,
	max_health: float,
) -> void:
	if _target_frame == null:
		return
	_target_name_label.text = display_name
	_target_name_label.add_theme_color_override(
		"font_color",
		EntityVisualEffectsType.target_color(kind),
	)
	_target_level_label.text = tr("hud_target_level") % level
	_target_health_bar.max_value = maxf(max_health, 1.0)
	_target_health_bar.value = clampf(health, 0.0, maxf(max_health, 1.0))
	_target_frame.modulate.a = 1.0


## Hides the frame of the target.
func hide_target() -> void:
	if _target_frame == null:
		return
	_target_frame.modulate.a = 0.0


## Refreshes the quick items of the action bar.
##
## The slots of the items follow the consumables the player carries.
func update_quick_items(items: Array) -> void:
	for index: int in range(ITEM_SLOT_COUNT):
		var slot_index: int = ABILITY_SLOT_COUNT + index
		if slot_index >= _slot_buttons.size():
			continue
		var button: Button = _slot_buttons[slot_index]
		var overlay: ColorRect = _slot_overlays[slot_index]
		var item_id: String = ""
		if index < items.size():
			item_id = str(items[index])
		_slot_item_ids[slot_index] = item_id
		overlay.visible = false
		if item_id.is_empty():
			button.text = tr("hud_slot_empty")
			button.disabled = true
			button.tooltip_text = ""
			continue
		var item_definition: Dictionary = _registry.get("items", {}).get(item_id, {})
		button.text = tr(str(item_definition.get("name_key", item_id)))
		button.disabled = false
		button.tooltip_text = tr("hud_slot_item_tooltip") % tr(
			str(item_definition.get("name_key", item_id))
		)


## Shows the progress of the character towards the next level.
func update_experience(experience: int, level: int) -> void:
	if _experience_bar == null:
		return
	var progression: Dictionary = _registry.get("progression", {})
	var current: Dictionary = progression.get("level_%d" % level, {})
	var next_level: int = mini(level + 1, progression.size())
	var next: Dictionary = progression.get("level_%d" % next_level, {})
	var required_now: int = int(current.get("experience_required", 0))
	var required_next: int = int(next.get("experience_required", required_now))
	_experience_bar.max_value = maxf(float(required_next - required_now), 1.0)
	_experience_bar.value = clampf(float(experience - required_now), 0.0, _experience_bar.max_value)
	_experience_bar.tooltip_text = tr("hud_experience_tooltip") % [
		int(experience),
		int(required_next),
	]


## Starts the visual cooldown of an ability.
##
## The server decides whether a cast is accepted, so the cooldown here is only
## the hint of the interface.
func start_cooldown(ability_id: String) -> void:
	var slot_index: int = ABILITY_IDS.find(ability_id)
	if slot_index < 0 or slot_index >= _slot_overlays.size():
		return
	var ability: Dictionary = _registry.get("abilities", {}).get(ability_id, {})
	var cooldown: float = float(ability.get("cooldown_seconds", 0.0))
	if cooldown <= 0.0:
		return
	var overlay: ColorRect = _slot_overlays[slot_index]
	overlay.visible = true
	overlay.anchor_top = 0.0
	overlay.anchor_bottom = 1.0
	overlay.offset_bottom = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(
		overlay,
		"anchor_bottom",
		0.0,
		cooldown,
	)
	tween.tween_callback(func() -> void: overlay.visible = false)


## Builds the frame of the character.
func _build_unit_frame() -> void:
	_unit_frame = PanelContainer.new()
	_unit_frame.name = "UnitFrame"
	_unit_frame.anchor_left = 0.0
	_unit_frame.anchor_top = 0.0
	_unit_frame.offset_left = 24.0
	_unit_frame.offset_top = 16.0
	_unit_frame.offset_right = 296.0
	_unit_frame.offset_bottom = 128.0
	add_child(_unit_frame)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "UnitFrameRoot"
	root.add_theme_constant_override("separation", 2)
	_unit_frame.add_child(root)

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.name = "NameRow"
	root.add_child(name_row)

	_unit_name_label = Label.new()
	_unit_name_label.name = "NameLabel"
	_unit_name_label.text = tr("hud_unit_name")
	_unit_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_unit_name_label)

	_unit_level_badge = Label.new()
	_unit_level_badge.name = "LevelBadge"
	_unit_level_badge.text = tr("hud_level_badge") % 1
	_unit_level_badge.add_theme_stylebox_override("normal", _build_badge_style())
	_unit_level_badge.add_theme_color_override("font_color", Color(0.12, 0.1, 0.05))
	name_row.add_child(_unit_level_badge)

	_health_bar = _build_bar("HealthBar", Color(0.78, 0.24, 0.2))
	_health_value = _build_bar_row("HealthRow", _health_bar, "HealthValue")
	_resource_bar = _build_bar("ResourceBar", Color(0.29, 0.58, 0.95))
	_resource_value = _build_bar_row("ResourceRow", _resource_bar, "ResourceValue")

	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.text = tr("hud_gold") % 0
	root.add_child(_gold_label)


## Builds the frame of the target.
func _build_target_frame() -> void:
	_target_frame = PanelContainer.new()
	_target_frame.name = "TargetFrame"
	_target_frame.anchor_left = 0.0
	_target_frame.anchor_top = 0.0
	_target_frame.offset_left = 308.0
	_target_frame.offset_top = 16.0
	_target_frame.offset_right = 580.0
	_target_frame.offset_bottom = 100.0
	_target_frame.modulate.a = 0.0
	add_child(_target_frame)

	var root: VBoxContainer = VBoxContainer.new()
	root.name = "TargetFrameRoot"
	root.add_theme_constant_override("separation", 2)
	_target_frame.add_child(root)

	_target_name_label = Label.new()
	_target_name_label.name = "TargetNameLabel"
	_target_name_label.text = tr("hud_target_empty")
	root.add_child(_target_name_label)

	_target_level_label = Label.new()
	_target_level_label.name = "TargetLevelLabel"
	_target_level_label.text = tr("hud_target_level") % 1
	root.add_child(_target_level_label)

	_target_health_bar = _build_bar("TargetHealthBar", Color(0.78, 0.24, 0.2))
	root.add_child(_target_health_bar)


## Builds the action bar with the abilities and the quick items.
func _build_action_bar() -> void:
	_action_bar = PanelContainer.new()
	_action_bar.name = "ActionBar"
	_action_bar.anchor_left = 0.5
	_action_bar.anchor_top = 1.0
	_action_bar.anchor_right = 0.5
	_action_bar.anchor_bottom = 1.0
	_action_bar.offset_left = -300.0
	_action_bar.offset_top = -104.0
	_action_bar.offset_right = 300.0
	_action_bar.offset_bottom = -44.0
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_action_bar)

	var root: HBoxContainer = HBoxContainer.new()
	root.name = "ActionBarRoot"
	root.add_theme_constant_override("separation", 4)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.add_child(root)

	for index: int in range(TOTAL_SLOT_COUNT):
		var slot: VBoxContainer = VBoxContainer.new()
		slot.name = "Slot%d" % index
		slot.add_theme_constant_override("separation", 0)
		root.add_child(slot)

		var key_label: Label = Label.new()
		key_label.name = "KeyLabel"
		key_label.text = HOTKEYS[index]
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 11)
		key_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.42))
		slot.add_child(key_label)

		var button: Button = Button.new()
		button.name = "ActionButton"
		button.custom_minimum_size = Vector2(68.0, 46.0)
		button.text = tr("hud_slot_empty")
		button.disabled = true
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 12)
		slot.add_child(button)
		_slot_buttons.append(button)
		_slot_item_ids.append("")

		var overlay: ColorRect = ColorRect.new()
		overlay.name = "CooldownOverlay"
		overlay.color = Color(0.0, 0.0, 0.0, 0.55)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.visible = false
		button.add_child(overlay)
		_slot_overlays.append(overlay)

		if index < ABILITY_SLOT_COUNT:
			var ability_id: String = ABILITY_IDS[index]
			var ability: Dictionary = _registry.get("abilities", {}).get(ability_id, {})
			button.text = tr(str(ability.get("name_key", ability_id)))
			button.disabled = false
			button.tooltip_text = tr("hud_slot_ability_tooltip") % [
				tr(str(ability.get("name_key", ability_id))),
				HOTKEYS[index],
			]
			button.pressed.connect(_on_ability_pressed.bind(ability_id))
		else:
			button.pressed.connect(_on_item_pressed.bind(index))


## Builds the experience bar under the action bar.
func _build_experience_bar() -> void:
	_experience_bar = ProgressBar.new()
	_experience_bar.name = "ExperienceBar"
	_experience_bar.anchor_left = 0.5
	_experience_bar.anchor_top = 1.0
	_experience_bar.anchor_right = 0.5
	_experience_bar.anchor_bottom = 1.0
	_experience_bar.offset_left = -300.0
	_experience_bar.offset_top = -38.0
	_experience_bar.offset_right = 300.0
	_experience_bar.offset_bottom = -26.0
	_experience_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_experience_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_experience_bar.show_percentage = false
	_experience_bar.max_value = 1.0
	add_child(_experience_bar)


## Builds the quick access buttons.
func _build_quick_access() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.name = "QuickAccessBar"
	bar.anchor_left = 1.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -400.0
	bar.offset_top = -40.0
	bar.offset_right = -24.0
	bar.offset_bottom = -16.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)

	for action: String in QUICK_ACTIONS:
		var button: Button = Button.new()
		button.name = "%sButton" % action.capitalize()
		button.text = tr("hud_quick_%s" % action)
		button.tooltip_text = tr("hud_quick_%s_tooltip" % action)
		button.pressed.connect(_on_quick_action_pressed.bind(action))
		bar.add_child(button)
		_quick_buttons[action] = button


## Builds a bar of the interface.
func _build_bar(bar_name: String, fill_color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.name = bar_name
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(120.0, 14.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## Builds a row with a bar and the numbers of the bar.
func _build_bar_row(row_name: String, bar: ProgressBar, value_name: String) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 6)
	var parent: Node = _unit_frame.get_node("UnitFrameRoot")
	parent.add_child(row)
	row.add_child(bar)
	var value_label: Label = Label.new()
	value_label.name = value_name
	value_label.text = "0 / 0"
	value_label.custom_minimum_size = Vector2(74.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return value_label


## Builds the style of the badge of the level.
func _build_badge_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.7, 0.38, 0.95)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


## Sends the request of an ability.
func _on_ability_pressed(ability_id: String) -> void:
	ability_requested.emit(ability_id)


## Sends the request of a quick item.
func _on_item_pressed(slot_index: int) -> void:
	if slot_index >= _slot_item_ids.size():
		return
	var item_id: String = _slot_item_ids[slot_index]
	if item_id.is_empty():
		return
	item_use_requested.emit(item_id)


## Sends the request of a quick action.
func _on_quick_action_pressed(action: String) -> void:
	quick_action_requested.emit(action)


## Sends the request of the slot of a hotkey.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key_event: InputEventKey = event
	var index: int = SLOT_KEYS.find(key_event.keycode)
	if index < 0 or index >= _slot_buttons.size():
		return
	var button: Button = _slot_buttons[index]
	if button.disabled:
		return
	if index < ABILITY_SLOT_COUNT:
		_on_ability_pressed(ABILITY_IDS[index])
		return
	_on_item_pressed(index)
