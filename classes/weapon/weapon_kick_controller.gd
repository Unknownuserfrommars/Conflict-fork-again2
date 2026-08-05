class_name WeaponKickController
extends Node

# ============================================================
# 武器后坐程序动画（枪身可视位移/旋转）
#
# 之前开火时只有摄像机在动，枪本身纹丝不动——手上没有"东西被推了一下"
# 的感觉，这就是 JiYu 说的"手感缺点东西"。
#
# 这里用弹簧-阻尼模型驱动枪身，全部由物理量实时计算，不用 AnimationPlayer：
#   · 后推（沿枪身 +Z）      ← 由后坐冲量决定
#   · 枪口上跳（绕 X 轴）     ← 由角冲量决定
#   · 随机水平扭转（绕 Y 轴） ← 由角冲量的横向分量决定
#   · 侧滚（绕 Z 轴）        ← 上跳的一小部分，破除完全对称
# 松开后由弹簧拉回原位，带轻微过冲，不是线性插值。
#
# 依赖：BaseWeapon.fired 信号 + RecoilComponent 的物理快照。
# 参数全部在 WeaponKickConfig 里，可按枪调。
# ============================================================

var _weapon: BaseWeapon
var _cfg: WeaponKickConfig
var _target: Node3D              # 被位移的节点（武器自身）
var _rest_position: Vector3
var _rest_rotation: Vector3

# 弹簧状态：位移（米）与旋转（弧度）
var _offset: Vector3 = Vector3.ZERO
var _offset_vel: Vector3 = Vector3.ZERO
var _rot: Vector3 = Vector3.ZERO
var _rot_vel: Vector3 = Vector3.ZERO


func initialize(weapon: BaseWeapon, cfg: WeaponKickConfig = null) -> void:
	_weapon = weapon
	_cfg = cfg if cfg else WeaponKickConfig.new()
	_target = weapon
	# 静息位姿由 WeaponManager._align_to_grip() 设定，延迟一帧读取
	call_deferred("_capture_rest")
	if not weapon.fired.is_connected(_on_fired):
		weapon.fired.connect(_on_fired)


func _capture_rest() -> void:
	if is_instance_valid(_target):
		_rest_position = _target.position
		_rest_rotation = _target.rotation


## 配件变动会让 _align_to_grip() 重设枪身位姿，需要重新取静息值
func refresh_rest() -> void:
	call_deferred("_capture_rest")


func _on_fired() -> void:
	if not _weapon or not _weapon.recoil_component:
		return
	var snapshot: Dictionary = _weapon.recoil_component.get_physics_snapshot()
	# 角冲量（弧度/秒）：pitch 上跳、yaw 横摆。取不到就退回配置基准值。
	var pitch_impulse: float = float(snapshot.get("pitch_impulse_rad_s", _cfg.fallback_pitch_impulse))
	var yaw_impulse: float = float(snapshot.get("yaw_impulse_rad_s", 0.0))

	# 线速度：后推量与角冲量同源（都来自弹头动量），乘以配置系数
	_offset_vel.z += pitch_impulse * _cfg.push_per_pitch_impulse
	# 上跳：绕 X 轴负向 = 枪口抬起
	_rot_vel.x -= pitch_impulse * _cfg.pitch_gain
	# 横摆：每发左右随机，用角冲量的 yaw 分量 + 少量噪声
	var yaw_sign := 1.0 if randf() < 0.5 else -1.0
	_rot_vel.y += (yaw_impulse + _cfg.yaw_noise * yaw_sign) * _cfg.yaw_gain
	# 侧滚：跟随上跳的一部分，让动作不完全对称
	_rot_vel.z += pitch_impulse * _cfg.roll_gain * yaw_sign


func _process(delta: float) -> void:
	if not is_instance_valid(_target) or not _cfg:
		return
	# 临界阻尼弹簧：x'' = -k·x - c·x'
	_offset_vel = _spring_step(_offset, _offset_vel, _cfg.position_stiffness, _cfg.position_damping, delta)
	_offset += _offset_vel * delta
	_rot_vel = _spring_step(_rot, _rot_vel, _cfg.rotation_stiffness, _cfg.rotation_damping, delta)
	_rot += _rot_vel * delta

	# 限幅：极端连发下不至于把枪甩出视野
	_offset = _offset.limit_length(_cfg.max_offset)
	_rot.x = clampf(_rot.x, -_cfg.max_rotation, _cfg.max_rotation)
	_rot.y = clampf(_rot.y, -_cfg.max_rotation, _cfg.max_rotation)
	_rot.z = clampf(_rot.z, -_cfg.max_rotation, _cfg.max_rotation)

	_target.position = _rest_position + _offset
	_target.rotation = _rest_rotation + _rot


static func _spring_step(value: Vector3, velocity: Vector3, stiffness: float, damping: float, delta: float) -> Vector3:
	return velocity + (-value * stiffness - velocity * damping) * delta
