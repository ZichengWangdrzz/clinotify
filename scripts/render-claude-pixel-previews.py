#!/usr/bin/env python3
import argparse
import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw


FPS = 120
DURATION_SECONDS = 2
FRAME_COUNT = FPS * DURATION_SECONDS
GIF_FPS = 20
GIF_FRAME_COUNT = GIF_FPS * DURATION_SECONDS
W = 750
H = 1000
ORANGE = (217, 118, 82, 255)
BG = (250, 250, 250, 255)
BLACK = (0, 0, 0, 255)


def ease_in_out(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


def rect(draw, box, fill=ORANGE):
    draw.rectangle(tuple(int(v) for v in box), fill=fill)


def polygon(draw, points, fill=ORANGE):
    draw.polygon([(int(x), int(y)) for x, y in points], fill=fill)


def base_canvas():
    return Image.new("RGBA", (W, H), BG)


def draw_reference_body(draw, right_arm="straight", leg_offsets=None, bob=0):
    if leg_offsets is None:
        leg_offsets = [0, 0, 0, 0]

    y = int(bob)

    # Body and head proportions follow the supplied 750x1000 reference.
    rect(draw, (69, 204 + y, 682, 643 + y))
    rect(draw, (0, 348 + y, 69, 498 + y))

    if right_arm == "straight":
        rect(draw, (682, 348 + y, 750, 498 + y))
    else:
        draw_right_wave_arm(draw, right_arm, y)

    # Four long rectangular legs with the large center gap from the reference.
    legs = [
        (69, 643, 133, 795),
        (205, 643, 271, 795),
        (479, 643, 545, 795),
        (615, 643, 682, 795),
    ]
    for i, box in enumerate(legs):
        offset = int(leg_offsets[i])
        rect(draw, (box[0], box[1] + y + offset, box[2], box[3] + y + offset))

    draw_squint_eyes(draw, y)


def draw_squint_eyes(draw, y):
    # Thick pixel-chevron eyes matching the reference position and weight.
    left = [
        (133, 342 + y),
        (227, 381 + y),
        (227, 409 + y),
        (133, 448 + y),
        (133, 419 + y),
        (195, 395 + y),
        (133, 371 + y),
    ]
    right = [
        (620, 342 + y),
        (526, 381 + y),
        (526, 409 + y),
        (620, 448 + y),
        (620, 419 + y),
        (558, 395 + y),
        (620, 371 + y),
    ]
    polygon(draw, left, BLACK)
    polygon(draw, right, BLACK)


def draw_right_wave_arm(draw, pose, y):
    # Continuous linear arm travel. Avoid easing here so the exported 2s motion
    # does not read as slowed down in the middle.
    pose = max(0.0, min(1.0, float(pose)))
    if pose < 0.04:
        rect(draw, (682, 348 + y, 750, 498 + y))
        return

    arm_top = 348 - 96 * pose
    arm_bottom = 498 - 100 * pose
    hand_top = 348 - 160 * pose
    rect(draw, (682, arm_top + y, 724, arm_bottom + y))
    rect(draw, (724, hand_top + y, 750, hand_top + 64 + y))


def linear_key_value(t, keyframes):
    for index in range(len(keyframes) - 1):
        t0, v0 = keyframes[index]
        t1, v1 = keyframes[index + 1]
        if t0 <= t <= t1:
            local = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return v0 + (v1 - v0) * local
    return keyframes[-1][1]


def wave_pose(frame):
    # One complete 2s action at linear speed: rest -> raise -> wave -> return.
    t = frame / (FRAME_COUNT - 1)
    return linear_key_value(t, [
        (0.00, 0),
        (0.25, 1.00),
        (0.43, 0.62),
        (0.61, 1.00),
        (1.00, 0),
    ])


def render_wave_frame(frame):
    img = base_canvas()
    d = ImageDraw.Draw(img)
    draw_reference_body(d, right_arm=wave_pose(frame))
    return img


def render_squint_leg_wave_frame(frame):
    img = base_canvas()
    d = ImageDraw.Draw(img)
    phase = frame / (FRAME_COUNT - 1)
    offsets = []
    for index in range(4):
        # One linear traveling pulse over the feet. No sine/envelope easing.
        start = index * 0.18
        peak = start + 0.16
        end = start + 0.32
        if phase < start or phase > end:
            amount = 0
        elif phase <= peak:
            amount = (phase - start) / (peak - start)
        else:
            amount = 1 - ((phase - peak) / (end - peak))
        offsets.append(round(-26 * amount))
    draw_reference_body(d, right_arm="straight", leg_offsets=offsets)
    return img


def save_frames(kind, frame_func, work_dir):
    frames_dir = work_dir / kind
    if frames_dir.exists():
        shutil.rmtree(frames_dir)
    frames_dir.mkdir(parents=True)

    gif_indices = {
        round(index * (FRAME_COUNT - 1) / (GIF_FRAME_COUNT - 1))
        for index in range(GIF_FRAME_COUNT)
    }
    gif_frames = []
    for frame in range(FRAME_COUNT):
        img = frame_func(frame)
        img.save(frames_dir / f"{frame:04d}.png")
        # GIF preview is intentionally 20fps because GIF timing cannot represent
        # true 120fps. The MP4 keeps the full 120fps source motion.
        if frame in gif_indices:
            gif_frames.append(img)
    return frames_dir, gif_frames


def encode_mp4(frames_dir, output):
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-framerate",
            str(FPS),
            "-i",
            str(frames_dir / "%04d.png"),
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "12",
            "-tune",
            "animation",
            "-pix_fmt",
            "yuv420p",
            "-r",
            str(FPS),
            "-video_track_timescale",
            str(FPS),
            "-movflags",
            "+faststart",
            str(output),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def encode_gif(frames, output):
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=int(1000 / GIF_FPS),
        loop=0,
        disposal=2,
        optimize=False,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--work-dir", default="/tmp/clinotify-claude-pixel-frames")
    args = parser.parse_args()

    out_dir = Path(args.output_dir).expanduser()
    work_dir = Path(args.work_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    work_dir.mkdir(parents=True, exist_ok=True)

    wave_frames, wave_gif = save_frames("right-hand-wave", render_wave_frame, work_dir)
    legs_frames, legs_gif = save_frames("squint-leg-wave", render_squint_leg_wave_frame, work_dir)

    outputs = [
        out_dir / "Claude-Pixel-Right-Hand-Wave-120fps.mp4",
        out_dir / "Claude-Pixel-Right-Hand-Wave-preview.gif",
        out_dir / "Claude-Pixel-Squint-Leg-Wave-120fps.mp4",
        out_dir / "Claude-Pixel-Squint-Leg-Wave-preview.gif",
    ]
    encode_mp4(wave_frames, outputs[0])
    encode_gif(wave_gif, outputs[1])
    encode_mp4(legs_frames, outputs[2])
    encode_gif(legs_gif, outputs[3])

    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
