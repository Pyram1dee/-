"""Чтение и запись моделей GoldSrc (Half-Life / CS 1.6), формат studio MDL версии 10.

Структуры и смещения соответствуют studio.h из Half-Life SDK.
Запись поддерживает подмножество, достаточное для простых моделей:
  - произвольное число костей, у каждой вершины одна кость;
  - одна bodypart, одна submodel, меши со своей текстурой;
  - 8-битные текстуры с палитрой, хранятся в том же файле;
  - последовательности (sequences) с анимацией вращения/смещения костей.
Чтение используется для проверки: и наших файлов, и эталонных моделей.
"""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field

IDST = b"IDST"
VERSION = 10

HDR_FMT = "<4si64si" + "3f" * 5 + "i" + "ii" * 5 + "iii" + "iii" + "ii" * 2 + "iiii" + "ii"
HDR_SIZE = struct.calcsize(HDR_FMT)
BONE_FMT = "<32sii6i6f6f"
BONE_SIZE = struct.calcsize(BONE_FMT)
BBOX_FMT = "<ii3f3f"
BBOX_SIZE = struct.calcsize(BBOX_FMT)
SEQ_FMT = "<32sf" + "i" * 10 + "3fii3f3fii2i2f2fiiiiii"
SEQ_SIZE = struct.calcsize(SEQ_FMT)
SEQGROUP_FMT = "<32s64sii"
SEQGROUP_SIZE = struct.calcsize(SEQGROUP_FMT)
BODYPART_FMT = "<64siii"
BODYPART_SIZE = struct.calcsize(BODYPART_FMT)
MODEL_FMT = "<64sifiiiiiiiiii"
MODEL_SIZE = struct.calcsize(MODEL_FMT)
MESH_FMT = "<iiiii"
MESH_SIZE = struct.calcsize(MESH_FMT)
TEX_FMT = "<64siiii"
TEX_SIZE = struct.calcsize(TEX_FMT)
ATTACH_FMT = "<32sii3f3f3f3f"
ATTACH_SIZE = struct.calcsize(ATTACH_FMT)

assert HDR_SIZE == 244, HDR_SIZE
assert BONE_SIZE == 112, BONE_SIZE
assert SEQ_SIZE == 176, SEQ_SIZE
assert SEQGROUP_SIZE == 104, SEQGROUP_SIZE
assert BODYPART_SIZE == 76, BODYPART_SIZE
assert MODEL_SIZE == 112, MODEL_SIZE
assert TEX_SIZE == 80, TEX_SIZE
assert MESH_SIZE == 20, MESH_SIZE


def _cstr(b: bytes) -> str:
    return b.split(b"\0", 1)[0].decode("latin-1")


# ---------------------------------------------------------------------------
# Математика (как в engine/mathlib.c)
# ---------------------------------------------------------------------------

def angle_quaternion(a):
    """AngleQuaternion из HLSDK: a = (x, y, z) в радианах."""
    ang = a[2] * 0.5
    sy, cy = math.sin(ang), math.cos(ang)
    ang = a[1] * 0.5
    sp, cp = math.sin(ang), math.cos(ang)
    ang = a[0] * 0.5
    sr, cr = math.sin(ang), math.cos(ang)
    return (
        sr * cp * cy - cr * sp * sy,
        cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy,
        cr * cp * cy + sr * sp * sy,
    )


def quaternion_matrix(q, pos):
    x, y, z, w = q
    return [
        [1.0 - 2.0 * y * y - 2.0 * z * z, 2.0 * x * y - 2.0 * w * z, 2.0 * x * z + 2.0 * w * y, pos[0]],
        [2.0 * x * y + 2.0 * w * z, 1.0 - 2.0 * x * x - 2.0 * z * z, 2.0 * y * z - 2.0 * w * x, pos[1]],
        [2.0 * x * z - 2.0 * w * y, 2.0 * y * z + 2.0 * w * x, 1.0 - 2.0 * x * x - 2.0 * y * y, pos[2]],
    ]


def concat(a, b):
    out = [[0.0] * 4 for _ in range(3)]
    for i in range(3):
        for j in range(4):
            out[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j]
        out[i][3] += a[i][3]
    return out


def transform(m, v):
    return tuple(m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] + m[i][3] for i in range(3))


# ---------------------------------------------------------------------------
# Описание модели для записи
# ---------------------------------------------------------------------------

@dataclass
class Bone:
    name: str
    parent: int  # -1 для корня
    pos: tuple = (0.0, 0.0, 0.0)
    rot: tuple = (0.0, 0.0, 0.0)


@dataclass
class Texture:
    name: str
    width: int
    height: int
    pixels: bytes          # width*height индексов палитры
    palette: bytes         # 256*3 RGB


@dataclass
class Tri:
    """Треугольник: индексы вершин, нормалей и (s, t) в текселях."""
    v: tuple
    n: tuple
    st: tuple              # ((s,t), (s,t), (s,t))


@dataclass
class Mesh:
    skinref: int
    tris: list = field(default_factory=list)


@dataclass
class Sequence:
    label: str
    fps: float
    numframes: int
    loop: bool = False
    activity: int = 0
    # анимация: {bone_index: функция(frame) -> (pos(3), rot(3))}; кости без записи стоят в позе по умолчанию
    anim: dict = field(default_factory=dict)


@dataclass
class Model:
    name: str
    bones: list
    textures: list
    verts: list            # [(x,y,z)]
    vert_bone: list        # [bone]
    norms: list
    norm_bone: list
    meshes: list
    sequences: list
    hitboxes: list = field(default_factory=list)   # [(bone, group, mins, maxs)]
    eyeposition: tuple = (0.0, 0.0, 0.0)
    flags: int = 0


# ---------------------------------------------------------------------------
# Запись
# ---------------------------------------------------------------------------

class _Buf:
    def __init__(self):
        self.data = bytearray()

    def tell(self):
        return len(self.data)

    def align(self, n=4):
        while len(self.data) % n:
            self.data.append(0)

    def put(self, b):
        off = len(self.data)
        self.data += b
        return off


def _bbox(points):
    xs, ys, zs = zip(*points)
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def _pose_points(model: Model, seq: Sequence, frame: int):
    mats = []
    for i, b in enumerate(model.bones):
        pos, rot = b.pos, b.rot
        if i in seq.anim:
            pos, rot = seq.anim[i](frame)
        m = quaternion_matrix(angle_quaternion(rot), pos)
        if b.parent >= 0:
            m = concat(mats[b.parent], m)
        mats.append(m)
    return [transform(mats[model.vert_bone[k]], v) for k, v in enumerate(model.verts)]


def _encode_channel(values):
    """Кодирует канал анимации как один run: valid = total = len(values).
    Последнее значение дублируется, чтобы движок не читал за концом при интерполяции."""
    vals = list(values) + [values[-1]]
    if len(vals) > 255:
        raise ValueError("слишком много кадров для одного run")
    out = struct.pack("<BB", len(vals), len(vals))
    for v in vals:
        out += struct.pack("<h", max(-32767, min(32767, int(round(v)))))
    return out


def write_mdl(model: Model) -> bytes:
    nb = len(model.bones)
    # Масштабы каналов кости: для каждой кости и канала берём максимум отклонения по всем анимациям
    scale = [[1.0 / 32.0] * 3 + [math.pi / 32000.0] * 3 for _ in range(nb)]
    for seq in model.sequences:
        for bi, fn in seq.anim.items():
            b = model.bones[bi]
            base = list(b.pos) + list(b.rot)
            for f in range(seq.numframes):
                p, r = fn(f)
                cur = list(p) + list(r)
                for j in range(6):
                    need = abs(cur[j] - base[j]) / 32000.0
                    if need > scale[bi][j]:
                        scale[bi][j] = need

    buf = _Buf()
    buf.put(b"\0" * HDR_SIZE)

    # кости
    bone_index = buf.tell()
    for i, b in enumerate(model.bones):
        buf.put(struct.pack(BONE_FMT, b.name.encode()[:31], b.parent, 0,
                            *([-1] * 6), *b.pos, *b.rot, *scale[i]))

    # hitboxes
    hitbox_index = buf.tell()
    for bone, group, mins, maxs in model.hitboxes:
        buf.put(struct.pack(BBOX_FMT, bone, group, *mins, *maxs))

    # последовательности (заполняем позже, когда известны animindex)
    seq_index = buf.tell()
    buf.put(b"\0" * (SEQ_SIZE * len(model.sequences)))

    seqgroup_index = buf.tell()
    buf.put(struct.pack(SEQGROUP_FMT, b"default", b"", 0, 0))

    # анимации: для seqgroup 0 animindex считается от начала файла
    anim_offsets = []
    for seq in model.sequences:
        buf.align(2)
        start = buf.tell()
        table = bytearray(12 * nb)
        buf.put(bytes(table))
        for bi in range(nb):
            b = model.bones[bi]
            if bi not in seq.anim:
                continue
            base = list(b.pos) + list(b.rot)
            frames = [seq.anim[bi](f) for f in range(seq.numframes)]
            offs = [0] * 6
            for j in range(6):
                vals = [((list(p) + list(r))[j] - base[j]) / scale[bi][j] for p, r in frames]
                if all(abs(v) < 0.5 for v in vals):
                    continue
                pos_in_table = start + 12 * bi
                off = buf.tell() - pos_in_table
                if off > 0xFFFF:
                    raise ValueError("смещение анимации больше 65535")
                buf.put(_encode_channel(vals))
                offs[j] = off
            struct.pack_into("<6H", buf.data, start + 12 * bi, *offs)
        anim_offsets.append(start)

    # bbox последовательностей
    for k, seq in enumerate(model.sequences):
        pts = []
        for f in range(seq.numframes):
            pts += _pose_points(model, seq, f)
        mins, maxs = _bbox(pts)
        flags = 1 if seq.loop else 0  # STUDIO_LOOPING
        struct.pack_into(SEQ_FMT, buf.data, seq_index + k * SEQ_SIZE,
                         seq.label.encode()[:31], seq.fps, flags, seq.activity, 1 if seq.activity else 0,
                         0, 0,                      # events
                         seq.numframes,
                         0, 0,                      # pivots
                         0, 0, 0.0, 0.0, 0.0,       # motion
                         0, 0,                      # automove
                         *mins, *maxs,
                         1, anim_offsets[k],        # numblends, animindex
                         0, 0, 0.0, 0.0, 1.0, 0.0, 0,
                         0,                         # seqgroup
                         0, 0, 0,                   # nodes
                         k)                         # nextseq

    # bodypart / model / mesh / verts
    buf.align(4)
    bodypart_index = buf.tell()
    buf.put(b"\0" * BODYPART_SIZE)
    model_index = buf.tell()
    buf.put(b"\0" * MODEL_SIZE)

    vertinfo = buf.put(bytes(model.vert_bone))
    buf.align(4)
    norminfo = buf.put(bytes(model.norm_bone))
    buf.align(4)
    vertindex = buf.put(b"".join(struct.pack("<3f", *v) for v in model.verts))
    normindex = buf.put(b"".join(struct.pack("<3f", *n) for n in model.norms))

    mesh_index = buf.tell()
    buf.put(b"\0" * (MESH_SIZE * len(model.meshes)))
    for k, mesh in enumerate(model.meshes):
        buf.align(2)
        tri_index = buf.tell()
        cmds = bytearray()
        for t in mesh.tris:
            # каждый треугольник — отдельная полоса из 3 вершин (count = 3)
            cmds += struct.pack("<h", 3)
            for i in range(3):
                cmds += struct.pack("<4h", t.v[i], t.n[i], int(round(t.st[i][0])), int(round(t.st[i][1])))
        cmds += struct.pack("<h", 0)
        buf.put(bytes(cmds))
        nnorms = len({n for t in mesh.tris for n in t.n})
        struct.pack_into(MESH_FMT, buf.data, mesh_index + k * MESH_SIZE,
                         len(mesh.tris), tri_index, mesh.skinref, nnorms, 0)

    radius = max(math.sqrt(x * x + y * y + z * z) for x, y, z in model.verts)
    struct.pack_into(MODEL_FMT, buf.data, model_index,
                     b"body", 0, radius, len(model.meshes), mesh_index,
                     len(model.verts), vertinfo, vertindex,
                     len(model.norms), norminfo, normindex, 0, 0)
    struct.pack_into(BODYPART_FMT, buf.data, bodypart_index, b"body", 1, 1, model_index)

    # текстуры и skins
    buf.align(4)
    texture_index = buf.tell()
    buf.put(b"\0" * (TEX_SIZE * len(model.textures)))
    skin_index = buf.tell()
    buf.put(b"".join(struct.pack("<h", i) for i in range(len(model.textures))))
    buf.align(4)
    texturedata_index = buf.tell()
    for k, tex in enumerate(model.textures):
        assert len(tex.pixels) == tex.width * tex.height and len(tex.palette) == 768
        off = buf.put(tex.pixels + tex.palette)
        struct.pack_into(TEX_FMT, buf.data, texture_index + k * TEX_SIZE,
                         tex.name.encode()[:63], 0, tex.width, tex.height, off)
    buf.align(4)

    mins, maxs = _bbox(model.verts)
    struct.pack_into(HDR_FMT, buf.data, 0,
                     IDST, VERSION, model.name.encode()[:63], len(buf.data),
                     *model.eyeposition, *mins, *maxs, *mins, *maxs,
                     model.flags,
                     nb, bone_index,
                     0, 0,
                     len(model.hitboxes), hitbox_index,
                     len(model.sequences), seq_index,
                     1, seqgroup_index,
                     len(model.textures), texture_index, texturedata_index,
                     len(model.textures), 1, skin_index,
                     1, bodypart_index,
                     0, 0,
                     0, 0, 0, 0,
                     0, 0)
    return bytes(buf.data)


# ---------------------------------------------------------------------------
# Чтение (для проверки)
# ---------------------------------------------------------------------------

class MdlError(Exception):
    pass


def read_mdl(data: bytes) -> dict:
    if len(data) < HDR_SIZE:
        raise MdlError("файл короче заголовка")
    h = struct.unpack_from(HDR_FMT, data, 0)
    ident, version, name, length = h[0], h[1], _cstr(h[2]), h[3]
    if ident != IDST:
        raise MdlError(f"неверная сигнатура {ident!r}")
    if version != VERSION:
        raise MdlError(f"версия {version}, нужна 10")
    if length != len(data):
        raise MdlError(f"length в заголовке {length} != размер файла {len(data)}")
    (numbones, boneindex, numbc, bcindex, numhb, hbindex, numseq, seqindex,
     numsg, sgindex) = h[20:30]
    numtex, texindex, texdataindex, numskinref, numskinfam, skinindex = h[30:36]
    numbp, bpindex, numatt, attindex = h[36:40]

    def check(off, size, what):
        if off < 0 or off + size > len(data):
            raise MdlError(f"{what}: выход за пределы файла (off={off}, size={size})")

    out = {"name": name, "length": length, "flags": h[19], "bones": [], "sequences": [],
           "textures": [], "bodyparts": [], "hitboxes": numhb, "attachments": numatt,
           "seqgroups": numsg, "skinref": numskinref, "skinfamilies": numskinfam}

    check(boneindex, numbones * BONE_SIZE, "bones")
    for i in range(numbones):
        b = struct.unpack_from(BONE_FMT, data, boneindex + i * BONE_SIZE)
        if not (-1 <= b[1] < i):
            raise MdlError(f"кость {i}: родитель {b[1]} должен быть раньше")
        out["bones"].append({"name": _cstr(b[0]), "parent": b[1],
                             "value": b[9:15], "scale": b[15:21]})

    check(sgindex, numsg * SEQGROUP_SIZE, "seqgroups")
    sg0_data = struct.unpack_from(SEQGROUP_FMT, data, sgindex)[3] if numsg else 0
    check(seqindex, numseq * SEQ_SIZE, "sequences")
    for i in range(numseq):
        s = struct.unpack_from(SEQ_FMT, data, seqindex + i * SEQ_SIZE)
        seq = {"label": _cstr(s[0]), "fps": s[1], "flags": s[2], "activity": s[3],
               "numframes": s[7], "numblends": s[23], "animindex": s[24], "seqgroup": s[32]}
        if seq["numframes"] < 1:
            raise MdlError(f"sequence {seq['label']}: numframes < 1")
        if seq["seqgroup"] == 0:
            check(sg0_data + seq["animindex"], 12 * numbones * seq["numblends"], f"anim {seq['label']}")
        out["sequences"].append(seq)

    check(texindex, numtex * TEX_SIZE, "textures")
    if texindex:
        for i in range(numtex):
            t = struct.unpack_from(TEX_FMT, data, texindex + i * TEX_SIZE)
            check(t[4], t[2] * t[3] + 768, f"texture {_cstr(t[0])}")
            out["textures"].append({"name": _cstr(t[0]), "flags": t[1], "width": t[2],
                                    "height": t[3], "index": t[4]})
    check(skinindex, 2 * numskinref * numskinfam, "skins")
    skins = struct.unpack_from(f"<{numskinref * numskinfam}h", data, skinindex) if numskinref else ()
    for s in skins:
        if texindex and not (0 <= s < numtex):
            raise MdlError(f"skin ссылается на текстуру {s}")

    check(bpindex, numbp * BODYPART_SIZE, "bodyparts")
    for i in range(numbp):
        bp = struct.unpack_from(BODYPART_FMT, data, bpindex + i * BODYPART_SIZE)
        part = {"name": _cstr(bp[0]), "models": []}
        check(bp[3], bp[1] * MODEL_SIZE, "models")
        for m in range(bp[1]):
            md = struct.unpack_from(MODEL_FMT, data, bp[3] + m * MODEL_SIZE)
            nummesh, meshindex, numverts, vinfo, vindex, numnorms, ninfo, nindex = md[3:11]
            check(vindex, numverts * 12, "verts")
            check(vinfo, numverts, "vertinfo")
            check(nindex, numnorms * 12, "norms")
            check(meshindex, nummesh * MESH_SIZE, "meshes")
            vbones = data[vinfo:vinfo + numverts]
            if numverts and max(vbones) >= numbones:
                raise MdlError("вершина ссылается на несуществующую кость")
            model = {"name": _cstr(md[0]), "numverts": numverts, "numnorms": numnorms,
                     "verts": [struct.unpack_from("<3f", data, vindex + 12 * k) for k in range(numverts)],
                     "vert_bone": list(vbones), "meshes": []}
            for k in range(nummesh):
                numtris, triindex, skinref, mnorms, _ = struct.unpack_from(MESH_FMT, data, meshindex + k * MESH_SIZE)
                if numskinref and not (0 <= skinref < numskinref):
                    raise MdlError(f"меш {k}: skinref {skinref} вне диапазона")
                tris = _read_tricmds(data, triindex, numverts, numnorms)
                model["meshes"].append({"numtris": numtris, "skinref": skinref, "tris": tris})
            part["models"].append(model)
        out["bodyparts"].append(part)
    out["skins"] = list(skins)
    out["_data"] = data
    out["_boneindex"] = boneindex
    out["_sg0"] = sg0_data
    return out


def _read_tricmds(data, off, numverts, numnorms):
    tris = []
    while True:
        if off + 2 > len(data):
            raise MdlError("команды треугольников выходят за пределы файла")
        (count,) = struct.unpack_from("<h", data, off)
        off += 2
        if count == 0:
            break
        fan = count < 0
        n = abs(count)
        pts = []
        for _ in range(n):
            v, nn, s, t = struct.unpack_from("<4h", data, off)
            off += 8
            if not (0 <= v < numverts) or not (0 <= nn < numnorms):
                raise MdlError(f"tricmd: индекс вершины {v}/{numverts} или нормали {nn}/{numnorms}")
            pts.append((v, s, t))
        for i in range(2, n):
            if fan:
                tris.append((pts[0], pts[i - 1], pts[i]))
            elif i % 2:
                tris.append((pts[i - 1], pts[i - 2], pts[i]))
            else:
                tris.append((pts[i - 2], pts[i - 1], pts[i]))
    return tris


def anim_value(data, anim_off, bone, channel, frame, bone_info):
    """Значение канала кости на целом кадре — алгоритм R_StudioCalcBone* движка."""
    offs = struct.unpack_from("<6H", data, anim_off + 12 * bone)
    base = bone_info["value"][channel]
    if offs[channel] == 0:
        return base
    p = anim_off + 12 * bone + offs[channel]
    k = frame
    while True:
        valid, total = struct.unpack_from("<BB", data, p)
        if total == 0:
            raise MdlError("run с total=0")
        if total > k:
            break
        k -= total
        p += 2 * (valid + 1)
    if valid > k:
        (v,) = struct.unpack_from("<h", data, p + 2 * (k + 1))
    else:
        (v,) = struct.unpack_from("<h", data, p + 2 * valid)
    return base + v * bone_info["scale"][channel]


def pose(m: dict, seq_index: int, frame: int):
    """Мировые матрицы костей для кадра последовательности."""
    data = m["_data"]
    seq = m["sequences"][seq_index]
    anim_off = m["_sg0"] + seq["animindex"]
    mats = []
    for i, b in enumerate(m["bones"]):
        vals = [anim_value(data, anim_off, i, j, frame, b) for j in range(6)]
        mat = quaternion_matrix(angle_quaternion(vals[3:]), vals[:3])
        if b["parent"] >= 0:
            mat = concat(mats[b["parent"]], mat)
        mats.append(mat)
    return mats


def texture_rgb(m: dict, index: int):
    t = m["textures"][index]
    data = m["_data"]
    w, h, off = t["width"], t["height"], t["index"]
    pix = data[off:off + w * h]
    pal = data[off + w * h: off + w * h + 768]
    return w, h, pix, pal
