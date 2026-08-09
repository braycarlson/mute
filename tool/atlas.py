#!/usr/bin/env python3
"""Bake a DejaVu Sans glyph atlas into raw coverage masks plus a Zig metrics table.

Emits one 8 bit alpha mask per face under asset/ and src/ui/atlas.zig, which the
software rasterizer indexes when it blits text. Advances are stored in 1/64 of a
pixel so draw_run can carry the rounding error across a run instead of dropping
it at every glyph. Run through `just atlas`. Needs python3 with Pillow and the
fonts-dejavu-core package, or DEJAVU_FONTS pointing at the directory holding it.
"""

import os
import sys

from PIL import Image, ImageFont

FONT_DIRECTORIES = [
    os.environ.get("DEJAVU_FONTS", ""),
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/TTF",
    "/usr/local/share/fonts",
    os.path.join(os.environ.get("WINDIR", "C:\\Windows"), "Fonts"),
    os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "Windows", "Fonts"),
    os.path.expanduser("~/.local/share/fonts"),
    os.path.expanduser("~/.fonts"),
]

FACES = [
    ("regular_small", "DejaVuSans.ttf", 12),
    ("bold_small", "DejaVuSans-Bold.ttf", 12),
    ("regular_large", "DejaVuSans.ttf", 13),
]

ATLAS_WIDTH = 256
ADVANCE_SCALE = 64
ADVANCE_MAX = 65535
FALLBACK = "\ufffd"

ASCII_FIRST = 0x20
ASCII_LAST = 0x7E
LATIN_FIRST = 0xA0
LATIN_LAST = 0xFF


def codepoints():
    values = list(range(ASCII_FIRST, ASCII_LAST + 1))
    values += list(range(LATIN_FIRST, LATIN_LAST + 1))

    return values


def locate(name):
    for directory in FONT_DIRECTORIES:
        if not directory or not os.path.isdir(directory):
            continue

        candidate = os.path.join(directory, name)

        if os.path.isfile(candidate):
            return candidate

    return None


def load(name, size):
    path = locate(name)

    if path is None:
        return None, None

    return ImageFont.truetype(path, size), path


def render_face(font):
    glyphs = []

    for value in codepoints() + [ord(FALLBACK)]:
        character = chr(value)
        mask = font.getmask(character, mode="L")
        width, height = mask.size
        bbox = font.getbbox(character)
        advance = int(round(font.getlength(character) * ADVANCE_SCALE))

        pixels = bytes(mask) if width and height else b""

        glyphs.append(
            {
                "advance": min(max(advance, 0), ADVANCE_MAX),
                "bearing_x": int(bbox[0]),
                "bearing_y": int(bbox[1]),
                "width": width,
                "height": height,
                "pixels": pixels,
            }
        )

    ascent, descent = font.getmetrics()

    return glyphs, ascent, descent


def pack(glyphs):
    x = 0
    y = 0
    row_height = 0

    for glyph in glyphs:
        if x + glyph["width"] > ATLAS_WIDTH:
            x = 0
            y += row_height
            row_height = 0

        glyph["x"] = x
        glyph["y"] = y

        x += glyph["width"] + 1
        row_height = max(row_height, glyph["height"] + 1)

    return y + row_height


def compose(glyphs, height):
    image = Image.new("L", (ATLAS_WIDTH, height), 0)

    for glyph in glyphs:
        if not glyph["width"] or not glyph["height"]:
            continue

        patch = Image.frombytes("L", (glyph["width"], glyph["height"]), glyph["pixels"])

        image.paste(patch, (glyph["x"], glyph["y"]))

    return image


def clamp(value, low, high):
    return max(low, min(high, value))


def emit_zig(faces, target):
    lines = []

    lines.append("pub const Glyph = struct {")
    lines.append("    advance_scaled: u16,")
    lines.append("    height: u8,")
    lines.append("    left: i8,")
    lines.append("    top: i8,")
    lines.append("    width: u8,")
    lines.append("    x: u16,")
    lines.append("    y: u16,")
    lines.append("};")
    lines.append("")
    lines.append("pub const advance_scale: i32 = %d;" % ADVANCE_SCALE)
    lines.append("pub const ascii_first: u32 = 0x%02X;" % ASCII_FIRST)
    lines.append("pub const ascii_last: u32 = 0x%02X;" % ASCII_LAST)
    lines.append("pub const latin_first: u32 = 0x%02X;" % LATIN_FIRST)
    lines.append("pub const latin_last: u32 = 0x%02X;" % LATIN_LAST)
    lines.append("")

    total = len(codepoints()) + 1

    lines.append("pub const glyph_count: u32 = %d;" % total)
    lines.append("pub const fallback_index: u32 = %d;" % (total - 1))
    lines.append("pub const atlas_width: u32 = %d;" % ATLAS_WIDTH)
    lines.append("")

    for name, glyphs, height, ascent, descent in faces:
        lines.append("pub const %s = struct {" % name)
        lines.append("    pub const ascent: u32 = %d;" % ascent)
        lines.append("    pub const descent: u32 = %d;" % descent)
        lines.append("    pub const height: u32 = %d;" % height)
        lines.append("    pub const line_height: u32 = %d;" % (ascent + descent))
        lines.append("")
        lines.append("    pub const glyphs = [glyph_count]Glyph{")

        for glyph in glyphs:
            lines.append(
                "        .{ .advance_scaled = %d, .height = %d, .left = %d, "
                ".top = %d, .width = %d, .x = %d, .y = %d },"
                % (
                    glyph["advance"],
                    glyph["height"],
                    clamp(glyph["bearing_x"], -128, 127),
                    clamp(glyph["bearing_y"], -128, 127),
                    glyph["width"],
                    glyph["x"],
                    glyph["y"],
                )
            )

        lines.append("    };")
        lines.append("};")
        lines.append("")

    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))


def main():
    faces = []
    source = None

    for name, filename, size in FACES:
        font, path = load(filename, size)

        if font is None:
            print("atlas: %s is missing; install fonts-dejavu-core or set DEJAVU_FONTS" % filename)

            return 1

        source = os.path.dirname(path)

        glyphs, ascent, descent = render_face(font)
        height = pack(glyphs)
        image = compose(glyphs, height)

        target = os.path.join("asset", "atlas_%s.a8" % name)

        with open(target, "wb") as handle:
            handle.write(image.tobytes())

        print("atlas: wrote %s (%dx%d)" % (target, ATLAS_WIDTH, height))

        faces.append((name, glyphs, height, ascent, descent))

    emit_zig(faces, os.path.join("src", "ui", "atlas.zig"))

    print("atlas: wrote src/ui/atlas.zig from %s" % source)

    return 0


if __name__ == "__main__":
    sys.exit(main())
