"""雨夜老街 —— 第一次验证用的场景清单（正式版这一步由 agent 按提示词写同样格式的 JSON）。

    python3 street_spec.py > spec.json

坐标：米；街沿 +Y 延伸，街心 x=0，地面 z=0。形状只有 box / cyl / ball 三种，
look 是材质的名字（Blender 脚本里有表）。深度控制只需要粗几何，白模越粗越稳。
"""
import json, random

rnd = random.Random(7)
objs = []
def box(at, size, look): objs.append({"shape": "box", "at": at, "size": size, "look": look})
def cyl(at, r, h, look): objs.append({"shape": "cyl", "at": at, "r": r, "h": h, "look": look})
def ball(at, r, look): objs.append({"shape": "ball", "at": at, "r": r, "look": look})

FACADE = 3.2                                   # 街宽 6.4 米
for side in (-1, 1):
    y = -8.0
    while y < 75:
        w = rnd.uniform(4.0, 6.5)              # 一间铺面沿街的宽度
        h = rnd.choice([5.8, 6.4, 7.2, 8.6])   # 两层 / 三层
        face = side * (FACADE + rnd.uniform(0.0, 0.35))
        depth = 5.0
        cx = face + side * depth / 2
        box([cx, y + w / 2, h / 2], [depth, w - 0.12, h], rnd.choice(["wall", "wall2"]))
        # 屋檐：一道挑出来的薄板
        box([face - side * 0.35, y + w / 2, h + 0.1], [0.9, w, 0.18], "roof")
        # 底层店面：雨棚挑进街里 0.9 米
        box([face - side * 0.45, y + w / 2, 2.75], [0.9, w - 0.5, 0.08], "awning")
        # 竖招牌：从墙上横着挑出来
        if rnd.random() < 0.7:
            sy = y + rnd.uniform(0.8, w - 0.8)
            box([face - side * 0.55, sy, 4.3], [0.7, 0.08, 1.7], rnd.choice(["sign", "sign_lit"]))
        # 灯笼：挂在雨棚边上
        k = y + 1.0
        while k < y + w - 0.6:
            if rnd.random() < 0.6:
                ball([face - side * 0.85, k, 2.35], 0.2, "lantern")
            k += rnd.uniform(1.6, 2.4)
        # 楼上的窗：贴在立面上的薄板，有的亮着
        for z in ([4.3] if h < 7 else [4.3, 6.6]):
            for wx in range(int((w - 1.0) // 1.6)):
                wy = y + 0.9 + wx * 1.6
                box([face - side * 0.03, wy + 0.5, z], [0.06, 0.9, 1.1], "window_lit" if rnd.random() < 0.45 else "window")
        y += w
# 路灯：街两边每 14 米一盏
for i, y in enumerate(range(2, 72, 14)):
    x = 2.55 * (1 if i % 2 else -1)
    cyl([x, y, 2.1], 0.06, 4.2, "metal")
    ball([x, y, 4.35], 0.18, "lamp")
# 横过街的电线
for y in (6, 21, 37, 55):
    box([0, y, 6.2], [7.0, 0.03, 0.03], "metal")
# 积水：路面上的薄片
for _ in range(14):
    box([rnd.uniform(-2.3, 2.3), rnd.uniform(0, 60), 0.005], [rnd.uniform(0.6, 1.8), rnd.uniform(0.8, 2.6), 0.01], "puddle")

spec = {
    "prompt": "雨夜的老街，镜头沿街往前推",
    "fps": 24, "frames": 124, "size": [864, 480],
    "sky": "night",
    "depth": {"near": 2.5, "far": 70.0},   # 近处的墙、灯笼、脚下路面在 2.5–5 米；0.8 米时整张图发暗、反差太小
    "ground": {"look": "wet_stone"},
    "objects": objs,
    # 镜头：t 是 0..1 的进度；at 是机位，look 是看向的点。之间按缓入缓出插值。
    "camera": {"lens": 28, "ease": "in_out",
               "keys": [{"t": 0.0, "at": [0.0, -2.0, 1.6], "look": [0.0, 30.0, 1.9]},
                        {"t": 1.0, "at": [0.0, 9.0, 1.6], "look": [0.0, 41.0, 1.9]}]},
    "keyframes": [0, 61, 123],
}
print(json.dumps(spec, ensure_ascii=False, indent=1))
