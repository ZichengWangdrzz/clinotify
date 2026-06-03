#!/usr/bin/env python3
import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 4
FRAME_W = 480
FRAME_H = 300


def sc(v):
    if isinstance(v, tuple):
        return tuple(int(x * S) for x in v)
    return int(v * S)


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, sc(size))
        except OSError:
            pass
    return ImageFont.load_default()


def downsample(img):
    return img.resize((FRAME_W, FRAME_H), Image.Resampling.LANCZOS)


def layer():
    return Image.new("RGBA", (FRAME_W * S, FRAME_H * S), (255, 255, 255, 0))


def draw_text_center(draw, box, text, fill, size, bold=False):
    f = font(size, bold)
    box = sc(box)
    bbox = draw.textbbox((0, 0), text, font=f)
    x = box[0] + ((box[2] - box[0]) - (bbox[2] - bbox[0])) / 2
    y = box[1] + ((box[3] - box[1]) - (bbox[3] - bbox[1])) / 2
    draw.text((x, y), text, font=f, fill=fill)


def soft_shadow(base, box, radius=24, alpha=55, blur=14):
    sh = layer()
    d = ImageDraw.Draw(sh)
    d.rounded_rectangle(sc(box), radius=sc(radius), fill=(0, 0, 0, alpha))
    base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(sc(blur))))


def radial_ellipse(draw, box, inner, outer, steps=22):
    box = sc(box)
    for i in range(steps, 0, -1):
        t = i / steps
        inset_x = (box[2] - box[0]) * (1 - t) / 2
        inset_y = (box[3] - box[1]) * (1 - t) / 2
        mix = 1 - t
        color = tuple(int(outer[c] * (1 - mix) + inner[c] * mix) for c in range(3)) + (255,)
        draw.ellipse(
            (
                box[0] + inset_x,
                box[1] + inset_y,
                box[2] - inset_x,
                box[3] - inset_y,
            ),
            fill=color,
        )


def rounded_line(draw, p1, p2, width, fill):
    p1 = sc(p1)
    p2 = sc(p2)
    width = sc(width)
    draw.line((p1, p2), fill=fill, width=width)
    r = width // 2
    draw.ellipse((p1[0] - r, p1[1] - r, p1[0] + r, p1[1] + r), fill=fill)
    draw.ellipse((p2[0] - r, p2[1] - r, p2[0] + r, p2[1] + r), fill=fill)


def draw_bubble(draw, x, y, title, subtitle, accent):
    box = (x, y, x + 170, y + 66)
    draw.rounded_rectangle(sc(box), radius=sc(14), fill=(255, 255, 255, 250), outline=accent, width=sc(2))
    tail = [sc((x + 8, y + 42)), sc((x - 12, y + 54)), sc((x + 12, y + 56))]
    draw.polygon(tail, fill=(255, 255, 255, 250))
    draw.line([tail[0], tail[1], tail[2]], fill=accent, width=sc(2))
    draw.text(sc((x + 18, y + 14)), title, font=font(17, True), fill=(32, 34, 36, 255))
    draw.text(sc((x + 18, y + 40)), subtitle, font=font(15), fill=(105, 108, 113, 255))


def draw_orange_mascot(draw, cx, cy, wave):
    orange = (217, 119, 87, 255)
    orange_dark = (190, 82, 45, 255)
    orange_light = (255, 151, 82)

    # Legs
    draw.rounded_rectangle(sc((cx - 31, cy + 62, cx - 10, cy + 96)), radius=sc(10), fill=orange_dark)
    draw.rounded_rectangle(sc((cx + 10, cy + 62, cx + 31, cy + 96)), radius=sc(10), fill=orange_dark)
    # Body
    radial_ellipse(draw, (cx - 54, cy - 8, cx + 54, cy + 82), orange_light, (222, 100, 49), 28)
    # Head
    radial_ellipse(draw, (cx - 58, cy - 84, cx + 58, cy + 30), orange_light, (220, 98, 47), 28)
    # Tuft
    draw.ellipse(sc((cx - 16, cy - 100, cx + 10, cy - 76)), fill=orange)
    draw.ellipse(sc((cx + 0, cy - 98, cx + 27, cy - 76)), fill=orange)
    # Resting arm
    rounded_line(draw, (cx - 48, cy + 10), (cx - 68, cy + 50), 17, orange)
    # Waving arm
    shoulder = (cx + 43, cy + 2)
    elbow = (cx + 68 + math.sin(wave) * 8, cy - 22 + math.cos(wave) * 8)
    hand = (cx + 86 + math.sin(wave + 0.8) * 9, cy - 53 + math.cos(wave + 0.4) * 10)
    rounded_line(draw, shoulder, elbow, 17, orange)
    rounded_line(draw, elbow, hand, 15, orange)
    draw.ellipse(sc((hand[0] - 12, hand[1] - 12, hand[0] + 12, hand[1] + 12)), fill=orange_light + (255,))
    # Face
    draw.ellipse(sc((cx - 28, cy - 42, cx - 17, cy - 22)), fill=(30, 30, 30, 255))
    draw.ellipse(sc((cx + 17, cy - 42, cx + 28, cy - 22)), fill=(30, 30, 30, 255))
    draw.arc(sc((cx - 21, cy - 20, cx + 21, cy + 10)), start=12, end=168, fill=(65, 35, 25, 255), width=sc(5))


def claude_done(output):
    frames = []
    for i in range(44):
        t = i / 43
        img = layer()
        soft_shadow(img, (42, 46, 438, 244), 26, 45, 16)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle(sc((42, 46, 438, 244)), radius=sc(26), fill=(255, 255, 255, 238), outline=(226, 228, 232, 255), width=sc(1))

        pop = 1 - (1 - min(t * 1.5, 1)) ** 3
        bob = math.sin(t * math.pi * 3) * 4
        cx, cy = 145, 142 + bob + (1 - pop) * 26
        draw_orange_mascot(d, cx, cy, t * math.pi * 7)

        draw_bubble(d, 254, 106, "Backend refactor", "Done", (217, 119, 87, 255))

        check_alpha = int(255 * min(max((t - 0.35) / 0.22, 0), 1))
        draw_text_center(d, (242, 66, 292, 116), "✓", (45, 156, 85, check_alpha), 39, True)
        burst = min(max((t - 0.48) / 0.36, 0), 1)
        for n in range(10):
            angle = n * math.tau / 10 + 0.2
            dist = 10 + 46 * burst
            x = 270 + math.cos(angle) * dist
            y = 86 + math.sin(angle) * dist
            alpha = int(210 * (1 - burst))
            d.ellipse(sc((x - 3, y - 3, x + 3, y + 3)), fill=(255, 173, 54, alpha))
        frames.append(downsample(img))
    frames[0].save(output, save_all=True, append_images=frames[1:], duration=36, loop=0, disposal=2)


def petal_layer(color, w=58, h=30):
    im = Image.new("RGBA", (sc(w), sc(h)), (255, 255, 255, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, sc(w), sc(h)), radius=sc(15), fill=color)
    return im


def paste_rotated(base, shape, center, angle, radius):
    rotated = shape.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)
    a = math.radians(angle)
    x = sc(center[0] + math.cos(a) * radius) - rotated.size[0] // 2
    y = sc(center[1] + math.sin(a) * radius) - rotated.size[1] // 2
    base.alpha_composite(rotated, (x, y))


def draw_blossom(base, cx, cy, progress):
    ink = (18, 20, 23, 255)
    blue = (26, 115, 232, 255)
    d = ImageDraw.Draw(base)
    for r_index in range(2):
        rt = (progress * 2 + r_index * 0.5) % 1
        radius = 46 + 70 * rt
        alpha = int(92 * (1 - rt))
        d.ellipse(sc((cx - radius, cy - radius, cx + radius, cy + radius)), outline=(26, 115, 232, alpha), width=sc(4))

    shape = petal_layer(ink)
    pulse = 1 + 0.05 * math.sin(progress * math.tau * 2)
    for ring in (0, 1):
        for i in range(6):
            angle = progress * 80 + i * 60 + ring * 30
            paste_rotated(base, shape, (cx, cy), angle, 26 * pulse + ring * 10)
    d = ImageDraw.Draw(base)
    d.ellipse(sc((cx - 28, cy - 28, cx + 28, cy + 28)), fill=(255, 255, 255, 255))
    d.ellipse(sc((cx - 13, cy - 13, cx + 13, cy + 13)), fill=ink)
    d.ellipse(sc((cx - 6, cy - 6, cx + 6, cy + 6)), fill=blue)


def codex_attention(output):
    frames = []
    for i in range(54):
        t = i / 54
        img = layer()
        soft_shadow(img, (42, 46, 438, 244), 26, 45, 16)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle(sc((42, 46, 438, 244)), radius=sc(26), fill=(255, 255, 255, 238), outline=(226, 228, 232, 255), width=sc(1))

        draw_blossom(img, 148, 146, t)
        d = ImageDraw.Draw(img)
        y = 74 + math.sin(t * math.tau * 2) * 5
        d.ellipse(sc((234, y, 284, y + 50)), fill=(26, 115, 232, 255))
        draw_text_center(d, (234, y - 1, 284, y + 49), "!", (255, 255, 255, 255), 34, True)
        draw_bubble(d, 254, 132, "Prompt review", "Needs you", (26, 115, 232, 255))
        frames.append(downsample(img))
    frames[0].save(output, save_all=True, append_images=frames[1:], duration=36, loop=0, disposal=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    out = Path(args.output_dir).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    claude_path = out / "CLINotify-Claude-Done.gif"
    codex_path = out / "CLINotify-Codex-Attention.gif"
    claude_done(claude_path)
    codex_attention(codex_path)
    print(claude_path)
    print(codex_path)


if __name__ == "__main__":
    main()
