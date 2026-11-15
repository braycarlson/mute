#!/usr/bin/env python3
from __future__ import annotations

import os

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageFont, features


ADVANCE_MAX = 65535
ADVANCE_SCALE = 64
ASCII_FIRST = 0x20
ASCII_LAST = 0x7E
ASSETS = Path(__file__).resolve().parent.parent / 'assets'
ATLAS_WIDTH = 256

FACES = (
    ('regular_small', 'DejaVuSans.ttf', 12),
    ('bold_small', 'DejaVuSans-Bold.ttf', 12),
    ('regular_large', 'DejaVuSans.ttf', 13),
)

FALLBACK = '\ufffd'

FONT_DIRECTORIES = (
    os.environ.get('DEJAVU_FONTS', ''),
    '/usr/share/fonts/truetype/dejavu',
    '/usr/share/fonts/TTF',
    '/usr/local/share/fonts',
    os.path.join(os.environ.get('WINDIR', 'C:\\Windows'), 'Fonts'),
    os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Microsoft', 'Windows', 'Fonts'),
    os.path.expanduser('~/.local/share/fonts'),
    os.path.expanduser('~/.fonts'),
)

LATIN_FIRST = 0xA0
LATIN_LAST = 0xFF
LINE_COLUMNS_MAX = 100
SOURCE = Path(__file__).resolve().parent.parent / 'src' / 'ui' / 'atlas.zig'


@dataclass(frozen=True)
class Face:
    ascent: int
    descent: int
    glyphs: tuple[Glyph, ...]
    height: int
    name: str


@dataclass
class Glyph:
    advance: int
    bearing_x: int
    bearing_y: int
    height: int
    pixels: bytes
    width: int
    x: int = 0
    y: int = 0


def main() -> None:
    directory = ''
    faces = []

    for name, filename, size in FACES:
        font, path = load(filename, size)
        glyphs, ascent, descent = face_render(font)
        height = pack(glyphs)
        image = compose(glyphs, height)
        atlas = image.tobytes()
        target = ASSETS / f'atlas_{name}.a8'
        face = Face(ascent=ascent, descent=descent, glyphs=tuple(glyphs), height=height, name=name)
        directory = os.path.dirname(path)

        target.write_bytes(atlas)
        faces.append(face)

        print(f'atlas: wrote assets/{target.name} ({ATLAS_WIDTH}x{height})')

    source_emit(faces, SOURCE)

    print(f'atlas: wrote src/ui/atlas.zig from {directory}')


def codepoints() -> list[int]:
    values = list(range(ASCII_FIRST, ASCII_LAST + 1))
    values += list(range(LATIN_FIRST, LATIN_LAST + 1))
    count = (ASCII_LAST - ASCII_FIRST + 1) + (LATIN_LAST - LATIN_FIRST + 1)

    if len(values) != count:
        message = f'The atlas covers {count} codepoints, not {len(values)}.'
        raise ValueError(message)

    return values


def compose(glyphs: list[Glyph], height: int) -> Image.Image:
    if any(glyph.x + glyph.width > ATLAS_WIDTH for glyph in glyphs):
        message = f'A glyph runs past the right edge of the {ATLAS_WIDTH} pixel atlas.'
        raise ValueError(message)

    if any(glyph.y + glyph.height > height for glyph in glyphs):
        message = f'A glyph runs past the bottom edge of the {height} pixel atlas.'
        raise ValueError(message)

    size = (ATLAS_WIDTH, height)
    image = Image.new('L', size, 0)

    for glyph in glyphs:
        if not glyph.width:
            continue

        if not glyph.height:
            continue

        extent = (glyph.width, glyph.height)
        position = (glyph.x, glyph.y)
        patch = Image.frombytes('L', extent, glyph.pixels)

        image.paste(patch, position)

    return image


def face_render(font: ImageFont.FreeTypeFont) -> tuple[list[Glyph], int, int]:
    if font.size <= 0:
        message = f'A face renders at a positive size, not {font.size}.'
        raise ValueError(message)

    glyphs = []

    for value in codepoints() + [ord(FALLBACK)]:
        character = chr(value)
        mask = font.getmask(character, mode='L')
        width, height = mask.size
        bbox = font.getbbox(character)
        advance = round(font.getlength(character) * ADVANCE_SCALE)
        area = width * height
        pixels = bytes(mask) if area else b''

        glyph = Glyph(
            advance=min(max(advance, 0), ADVANCE_MAX),
            bearing_x=int(bbox[0]),
            bearing_y=int(bbox[1]),
            height=height,
            pixels=pixels,
            width=width,
        )

        glyphs.append(glyph)

    ascent, descent = font.getmetrics()
    return glyphs, ascent, descent


def glyph_literal(glyph: Glyph) -> list[str]:
    if glyph.width > 255:
        message = f'A glyph is at most 255 pixels wide, not {glyph.width}.'
        raise ValueError(message)

    if glyph.height > 255:
        message = f'A glyph is at most 255 pixels tall, not {glyph.height}.'
        raise ValueError(message)

    if glyph.advance > ADVANCE_MAX:
        message = f'A glyph advances at most {ADVANCE_MAX} units, not {glyph.advance}.'
        raise ValueError(message)

    left = min(max(glyph.bearing_x, -128), 127)
    top = min(max(glyph.bearing_y, -128), 127)

    fields = [
        f'.advance_scaled = {glyph.advance}',
        f'.height = {glyph.height}',
        f'.left = {left}',
        f'.top = {top}',
        f'.width = {glyph.width}',
        f'.x = {glyph.x}',
        f'.y = {glyph.y}',
    ]

    single = '        .{ ' + ', '.join(fields) + ' },'

    if len(single) <= LINE_COLUMNS_MAX:
        return [single]

    nested = [f'            {field},' for field in fields]
    return ['        .{', *nested, '        },']


def load(name: str, size: int) -> tuple[ImageFont.FreeTypeFont, str]:
    if not name.endswith('.ttf'):
        message = f'A font file ends in .ttf, not {name}.'
        raise ValueError(message)

    if size <= 0:
        message = f'A font loads at a positive size, not {size}.'
        raise ValueError(message)

    if not features.check('raqm'):
        message = 'The atlas needs Raqm: the basic layout rounds each advance to a whole pixel.'
        raise RuntimeError(message)

    path = locate(name)
    font = ImageFont.truetype(path, size, layout_engine=ImageFont.Layout.RAQM)

    return font, path


def locate(name: str) -> str:
    if not name.endswith('.ttf'):
        message = f'A font file ends in .ttf, not {name}.'
        raise ValueError(message)

    if os.sep in name:
        message = f'A font is named by its file alone, not by the path {name}.'
        raise ValueError(message)

    for directory in FONT_DIRECTORIES:
        if not directory:
            continue

        if not os.path.isdir(directory):
            continue

        candidate = os.path.join(directory, name)

        if os.path.isfile(candidate):
            return candidate

    message = f'The font {name} is missing; install fonts-dejavu-core or set DEJAVU_FONTS.'
    raise FileNotFoundError(message)


def pack(glyphs: list[Glyph]) -> int:
    if len(glyphs) != len(codepoints()) + 1:
        message = f'An atlas packs {len(codepoints()) + 1} glyphs, not {len(glyphs)}.'
        raise ValueError(message)

    x = 0
    y = 0
    row_height = 0

    for glyph in glyphs:
        if x + glyph.width > ATLAS_WIDTH:
            x = 0
            y += row_height
            row_height = 0

        glyph.x = x
        glyph.y = y
        x += glyph.width + 1
        row_height = max(row_height, glyph.height + 1)

    height = y + row_height

    if any(glyph.y + glyph.height > height for glyph in glyphs):
        message = f'A packed glyph runs past the bottom edge of the {height} pixel atlas.'
        raise ValueError(message)

    return height


def source_emit(faces: list[Face], target: Path) -> None:
    if len(faces) != len(FACES):
        message = f'The atlas source carries {len(FACES)} faces, not {len(faces)}.'
        raise ValueError(message)

    if target.suffix != '.zig':
        message = f'The atlas source is a Zig file, not {target.name}.'
        raise ValueError(message)

    lines = []

    lines.append('pub const Glyph = struct {')
    lines.append('    advance_scaled: u16,')
    lines.append('    height: u8,')
    lines.append('    left: i8,')
    lines.append('    top: i8,')
    lines.append('    width: u8,')
    lines.append('    x: u16,')
    lines.append('    y: u16,')
    lines.append('};')
    lines.append('')
    lines.append(f'pub const advance_scale: i32 = {ADVANCE_SCALE};')
    lines.append(f'pub const ascii_first: u32 = 0x{ASCII_FIRST:02X};')
    lines.append(f'pub const ascii_last: u32 = 0x{ASCII_LAST:02X};')
    lines.append(f'pub const latin_first: u32 = 0x{LATIN_FIRST:02X};')
    lines.append(f'pub const latin_last: u32 = 0x{LATIN_LAST:02X};')

    total = len(codepoints()) + 1

    lines.append(f'pub const glyph_count: u32 = {total};')
    lines.append(f'pub const fallback_index: u32 = {total - 1};')
    lines.append(f'pub const width: u32 = {ATLAS_WIDTH};')
    lines.append('')

    for face in faces:
        lines.append(f'pub const {face.name} = struct {{')
        lines.append(f'    pub const ascent: u32 = {face.ascent};')
        lines.append(f'    pub const height: u32 = {face.height};')
        lines.append(f'    pub const line_height: u32 = {face.ascent + face.descent};')
        lines.append('')
        lines.append('    pub const glyphs = [glyph_count]Glyph{')

        for glyph in face.glyphs:
            literal = glyph_literal(glyph)

            lines.extend(literal)

        lines.append('    };')
        lines.append('};')
        lines.append('')

    source = '\n'.join(lines)

    target.write_text(source, encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
