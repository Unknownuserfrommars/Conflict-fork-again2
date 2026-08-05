extends CanvasLayer

## 弹药 HUD（右下角）
## 显示：膛内标记 + 当前弹匣余弹 / 备用弹总数 + 射击模式
## 数据来自 BaseWeapon.ammo_component，通过 ammo_count_changed 信号刷新，
## 换武器时自动重新挂接。
##
## 配色沿用设置页/改装界面，保持整体一致。

const FONT_PATH := "res://res/fonts/ConflictCJKUI.ttf"
const COL_TEXT := Color(0.945, 0.953, 0.961)
const COL_MUTED := Color(0.61, 0.64, 0.68)
const COL_LOW := Color(0.90, 0.62, 0.30)      # 余弹偏低
const COL_EMPTY := Color(0.84, 0.42, 0.39)    # 打空
const COL_PANEL := Color(0.063, 0.067, 0.075, 0.72)
const COL_BORDER := Color(1.0, 1.0, 1.0, 0.11)
const COL_RELOAD_TRACK := Color(1.0, 1.0, 1.0, 0.16)
const COL_RELOAD_PROGRESS := Color(0.945, 0.953, 0.961, 0.95)

## 余弹低于弹匣容量的该比例时变色提示
const LOW_AMMO_RATIO := 0.3

var _player
var _weapon: BaseWeapon
var _mag_label: Label
var _reserve_label: Label
var _mode_label: Label
var _debug_label: Label
var _chamber_dot: Panel
var _reload_countdown: ReloadCountdown


class ReloadCountdown extends Control:
	var remaining := 0.0
	var total := 1.0
	var track_color := Color.WHITE
	var progress_color := Color.WHITE
	var _time_label: Label

	func _init() -> void:
		custom_minimum_size = Vector2(56, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(font: Font) -> void:
		_time_label = Label.new()
		_time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_time_label.add_theme_font_size_override("font_size", 14)
		_time_label.add_theme_color_override("font_color", progress_color)
		if font:
			_time_label.add_theme_font_override("font", font)
		add_child(_time_label)

	func start(duration: float) -> void:
		total = maxf(duration, 0.001)
		remaining = maxf(duration, 0.0)
		visible = remaining > 0.0
		_update_visuals()

	func stop() -> void:
		remaining = 0.0
		visible = false

	func advance(delta: float) -> void:
		if not visible:
			return
		remaining = maxf(remaining - delta, 0.0)
		_update_visuals()
		if remaining <= 0.0:
			visible = false

	func _update_visuals() -> void:
		if _time_label:
			_time_label.text = "%.1f" % remaining
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 5.0
		var start_angle := -PI * 0.5
		draw_arc(center, radius, 0.0, TAU, 64, track_color, 4.0, true)
		var ratio := clampf(remaining / total, 0.0, 1.0)
		if ratio > 0.0:
			draw_arc(center, radius, start_angle, start_angle + TAU * ratio, 64, progress_color, 4.0, true)


func initialize(player) -> void:
	_player = player
	if _player.weapon_manager:
		_player.weapon_manager.weapon_changed.connect(_on_weapon_changed)
		# 初始化时武器可能已装备
		_on_weapon_changed(_player.weapon_manager.current_weapon)


func _ready() -> void:
	layer = 8  # 低于通知(10)与各类菜单
	_build_ui()
	set_process(true)


func _process(delta: float) -> void:
	if _reload_countdown:
		_reload_countdown.advance(delta)


func _build_ui() -> void:
	var theme := Theme.new()
	if ResourceLoader.exists(FONT_PATH):
		theme.default_font = load(FONT_PATH)

	var panel := PanelContainer.new()
	panel.theme = theme
	var box := StyleBoxFlat.new()
	box.bg_color = COL_PANEL
	box.border_color = COL_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", box)
	# 右下角
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# debug 构建多一行弹匣明细，需要更宽更高的面板
	panel.offset_left = -320.0 if OS.is_debug_build() else -230.0
	panel.offset_top = -112.0 if OS.is_debug_build() else -92.0
	panel.offset_right = -28.0
	panel.offset_bottom = -28.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# 换弹期间显示在弹药容量上方；隐藏时不占 HUD 空间。
	var countdown_center := CenterContainer.new()
	countdown_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(countdown_center)
	_reload_countdown = ReloadCountdown.new()
	_reload_countdown.track_color = COL_RELOAD_TRACK
	_reload_countdown.progress_color = COL_RELOAD_PROGRESS
	_reload_countdown.setup(theme.default_font)
	_reload_countdown.visible = false
	countdown_center.add_child(_reload_countdown)

	# 上排：膛内指示点 + 弹匣余弹 / 备弹
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# 主数字靠右贴边：右下角 HUD 的数字位数会变（30 → 9），
	# 靠右对齐才不会让整块 UI 左右跳动
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)

	_chamber_dot = Panel.new()
	_chamber_dot.custom_minimum_size = Vector2(8, 8)
	_chamber_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chamber_dot.tooltip_text = "膛内有弹"
	row.add_child(_chamber_dot)

	_mag_label = Label.new()
	_mag_label.add_theme_font_size_override("font_size", 34)
	_mag_label.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(_mag_label)

	_reserve_label = Label.new()
	_reserve_label.add_theme_font_size_override("font_size", 17)
	_reserve_label.add_theme_color_override("font_color", COL_MUTED)
	_reserve_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_reserve_label)

	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 12)
	_mode_label.add_theme_color_override("font_color", COL_MUTED)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_mode_label)

	# 调试行：全枪总弹数 + 各弹匣明细（仅 debug 构建显示）
	if OS.is_debug_build():
		_debug_label = Label.new()
		_debug_label.add_theme_font_size_override("font_size", 11)
		_debug_label.add_theme_color_override("font_color", COL_MUTED.darkened(0.1))
		_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vbox.add_child(_debug_label)

	_refresh()


func _on_weapon_changed(weapon) -> void:
	# 断开旧武器的信号，避免换枪后重复刷新
	if is_instance_valid(_weapon) and _weapon.ammo_component:
		if _weapon.ammo_component.ammo_count_changed.is_connected(_on_ammo_changed):
			_weapon.ammo_component.ammo_count_changed.disconnect(_on_ammo_changed)
		if _weapon.fire_mode_changed.is_connected(_on_fire_mode_changed):
			_weapon.fire_mode_changed.disconnect(_on_fire_mode_changed)
		if _weapon.reload_countdown_started.is_connected(_on_reload_countdown_started):
			_weapon.reload_countdown_started.disconnect(_on_reload_countdown_started)
		if _weapon.reload_finished.is_connected(_on_reload_finished):
			_weapon.reload_finished.disconnect(_on_reload_finished)
		if _weapon.reload_interrupted.is_connected(_on_reload_interrupted):
			_weapon.reload_interrupted.disconnect(_on_reload_interrupted)

	_weapon = weapon as BaseWeapon
	if is_instance_valid(_weapon):
		if _weapon.ammo_component:
			_weapon.ammo_component.ammo_count_changed.connect(_on_ammo_changed)
		_weapon.fire_mode_changed.connect(_on_fire_mode_changed)
		# 装卸弹匣会改变"有没有弹匣"与容量，必须跟着刷新
		if _weapon.attachment_manager:
			_weapon.attachment_manager.attachments_changed.connect(_refresh)
		_weapon.reload_countdown_started.connect(_on_reload_countdown_started)
		_weapon.reload_finished.connect(_on_reload_finished)
		_weapon.reload_interrupted.connect(_on_reload_interrupted)
	else:
		_stop_reload_countdown()
	_refresh()


func _on_ammo_changed(_current: int, _reserve: int) -> void:
	_refresh()


func _on_fire_mode_changed(_mode: String) -> void:
	_refresh()


func _on_reload_countdown_started(duration: float) -> void:
	if _reload_countdown:
		_reload_countdown.start(duration)


func _on_reload_finished() -> void:
	_stop_reload_countdown()


func _on_reload_interrupted(_completed_stages: Array) -> void:
	_stop_reload_countdown()


func _stop_reload_countdown() -> void:
	if _reload_countdown:
		_reload_countdown.stop()


## 主动刷新（外部改动弹药后可调用，例如调试重置）
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if not _mag_label:
		return
	if not is_instance_valid(_weapon) or not _weapon.ammo_component:
		_mag_label.text = "--"
		_reserve_label.text = ""
		_mode_label.text = ""
		_set_dot(false)
		return

	var ammo := _weapon.ammo_component
	var in_mag: int = ammo.get_current_magazine_count()
	var reserve: int = ammo.get_reserve_count()
	var has_magazine: bool = _weapon._get_attachment_config_of_type(MagazineConfig) != null

	if not has_magazine:
		# 拆了弹匣：不显示弹匣计数（枪上没有弹匣可读），
		# 只用膛内指示点提示"还有一发"。
		_mag_label.text = "--"
		_reserve_label.text = "无弹匣"
	else:
		# 显示"随时可打的发数" = 弹匣内 + 膛内那一发。
		# 只显示弹匣数会出现换弹后 30 跳 29 的怪现象：满弹匣插上后
		# 会有一发被推进膛，弹匣里确实只剩 29——但玩家手上仍是 30 发可打。
		# 膛内那一发另由指示点单独标示。
		_mag_label.text = str(in_mag + (1 if ammo.has_chambered_round() else 0))
		_reserve_label.text = "/ %d" % reserve

	# 余弹配色：空 → 红，低 → 橙，正常 → 白
	var capacity: float = float(_magazine_capacity())
	var ready_rounds: int = in_mag + (1 if ammo.has_chambered_round() else 0)
	var col := COL_TEXT
	if not has_magazine:
		col = COL_LOW if ammo.has_chambered_round() else COL_EMPTY
	elif ready_rounds <= 0:
		col = COL_EMPTY
	elif capacity > 0.0 and float(ready_rounds) / capacity <= LOW_AMMO_RATIO:
		col = COL_LOW
	_mag_label.add_theme_color_override("font_color", col)

	_set_dot(ammo.has_chambered_round())
	_mode_label.text = _mode_display(_weapon.current_fire_mode)
	_refresh_debug_line(ammo)


## 调试行：全枪总弹数、弹匣数量、各弹匣明细
## 例：总 174 发 · 6 匣 [29|30|30|30|30|25]
func _refresh_debug_line(ammo: AmmoComponent) -> void:
	if not _debug_label:
		return
	var breakdown: Array[int] = ammo.get_magazine_breakdown()
	var parts: PackedStringArray = []
	for i in breakdown.size():
		# 标记当前在用的弹匣
		parts.append(("*%d" % breakdown[i]) if i == ammo.current_magazine else str(breakdown[i]))
	_debug_label.text = "总 %d 发 · %d 匣 [%s]" % [
		ammo.get_total_rounds(), ammo.get_magazine_pool_size(), "|".join(parts)
	]


func _magazine_capacity() -> int:
	if not is_instance_valid(_weapon):
		return 0
	var mag := _weapon._get_attachment_config_of_type(MagazineConfig) as MagazineConfig
	if mag:
		return mag.magazine_capacity
	return 30


## 膛内指示点：有弹亮，空膛暗
func _set_dot(lit: bool) -> void:
	if not _chamber_dot:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = COL_TEXT if lit else Color(1, 1, 1, 0.13)
	box.set_corner_radius_all(4)
	_chamber_dot.add_theme_stylebox_override("panel", box)


func _mode_display(mode: String) -> String:
	match mode:
		"safe":  return "保险"
		"semi":  return "单点"
		"burst": return "连发"
		"auto":  return "自动"
		_: return mode
