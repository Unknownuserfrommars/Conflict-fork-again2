class_name WeaponKickConfig
extends Resource

# ============================================================
# 枪身后坐程序动画参数
# 全部为"物理量 → 视觉量"的换算系数与弹簧参数；
# 实际幅度由 RecoilPhysicsModel 的角冲量实时驱动，
# 换更重的枪/更强的枪口制退器，动作会自动变小。
# ============================================================

@export_group("换算增益 / Gain")
## 后推量系数：角冲量(rad/s) → 枪身后移(m)
@export var push_per_pitch_impulse: float = 0.055
## 枪口上跳系数：角冲量 → 绕 X 轴旋转
@export var pitch_gain: float = 0.85
## 水平摆动系数
@export var yaw_gain: float = 0.55
## 侧滚系数（取上跳的一小部分，破除左右完全对称）
@export var roll_gain: float = 0.18
## 每发水平摆动的随机噪声（rad/s），让连发不是一条直线
@export var yaw_noise: float = 0.35
## 取不到物理快照时的兜底角冲量
@export var fallback_pitch_impulse: float = 2.2

@export_group("回正弹簧 / Spring")
## 位移刚度：越大回位越快
@export var position_stiffness: float = 190.0
## 位移阻尼：略小于临界值，留一点过冲，回位不呆板
@export var position_damping: float = 22.0
## 旋转刚度
@export var rotation_stiffness: float = 150.0
## 旋转阻尼
@export var rotation_damping: float = 18.0

@export_group("限幅 / Clamp")
## 枪身最大位移（m）
@export var max_offset: float = 0.09
## 枪身最大旋转（弧度）
@export var max_rotation: float = 0.30
