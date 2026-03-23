#!/usr/bin/env python3

import argparse
from collections import deque
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Remove flat avatar background and preserve a transparent subject.")
    parser.add_argument("--input", required=True, help="Input PNG path.")
    parser.add_argument("--output", required=True, help="Output PNG path.")
    parser.add_argument("--threshold", type=int, default=30, help="RGB distance threshold for flood-filled background.")
    parser.add_argument("--corner-size", type=int, default=28, help="Corner sample size in pixels.")
    parser.add_argument("--blur-radius", type=float, default=1.4, help="Alpha feather radius.")
    parser.add_argument("--floor-alpha", type=int, default=6, help="Drop alpha values below this floor.")
    return parser.parse_args()


def average_color(image: Image.Image, x_range: Iterable[int], y_range: Iterable[int]) -> tuple[int, int, int]:
    pixels = image.load()
    total_r = total_g = total_b = count = 0

    for y in y_range:
        for x in x_range:
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            total_r += r
            total_g += g
            total_b += b
            count += 1

    if count == 0:
        return (0, 0, 0)

    return (
        round(total_r / count),
        round(total_g / count),
        round(total_b / count),
    )


def corner_samples(image: Image.Image, corner_size: int) -> list[tuple[int, int, int]]:
    width, height = image.size
    sample = max(8, min(corner_size, width // 5, height // 5))

    return [
        average_color(image, range(0, sample), range(0, sample)),
        average_color(image, range(width - sample, width), range(0, sample)),
        average_color(image, range(0, sample), range(height - sample, height)),
        average_color(image, range(width - sample, width), range(height - sample, height)),
    ]


def color_distance(pixel: tuple[int, int, int, int], sample: tuple[int, int, int]) -> float:
    r, g, b, _ = pixel
    sr, sg, sb = sample
    dr = r - sr
    dg = g - sg
    db = b - sb
    return (dr * dr + dg * dg + db * db) ** 0.5


def matches_background(pixel: tuple[int, int, int, int], samples: list[tuple[int, int, int]], threshold: int) -> bool:
    if pixel[3] == 0:
        return True
    return min(color_distance(pixel, sample) for sample in samples) <= threshold


def build_background_mask(image: Image.Image, samples: list[tuple[int, int, int]], threshold: int) -> Image.Image:
    width, height = image.size
    pixels = image.load()
    visited = bytearray(width * height)
    alpha = Image.new("L", (width, height), 255)
    alpha_pixels = alpha.load()
    queue: deque[tuple[int, int]] = deque()

    def index(x: int, y: int) -> int:
        return y * width + x

    def try_enqueue(x: int, y: int) -> None:
        idx = index(x, y)
        if visited[idx]:
            return
        visited[idx] = 1
        if matches_background(pixels[x, y], samples, threshold):
            alpha_pixels[x, y] = 0
            queue.append((x, y))

    for x in range(width):
        try_enqueue(x, 0)
        try_enqueue(x, height - 1)

    for y in range(height):
        try_enqueue(0, y)
        try_enqueue(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height:
                idx = index(nx, ny)
                if visited[idx]:
                    continue
                visited[idx] = 1
                if matches_background(pixels[nx, ny], samples, threshold):
                    alpha_pixels[nx, ny] = 0
                    queue.append((nx, ny))

    return alpha


def decontaminate_edges(image: Image.Image, alpha: Image.Image, matte_color: tuple[int, int, int], floor_alpha: int) -> Image.Image:
    rgba = image.copy().convert("RGBA")
    rgba_pixels = rgba.load()
    alpha_pixels = alpha.load()
    width, height = rgba.size
    matte_r, matte_g, matte_b = matte_color

    for y in range(height):
        for x in range(width):
            r, g, b, _ = rgba_pixels[x, y]
            a = alpha_pixels[x, y]

            if a <= floor_alpha:
                rgba_pixels[x, y] = (0, 0, 0, 0)
                continue

            if a >= 250:
                rgba_pixels[x, y] = (r, g, b, 255)
                continue

            alpha_ratio = a / 255.0
            out_r = round((r - matte_r * (1 - alpha_ratio)) / max(alpha_ratio, 1e-6))
            out_g = round((g - matte_g * (1 - alpha_ratio)) / max(alpha_ratio, 1e-6))
            out_b = round((b - matte_b * (1 - alpha_ratio)) / max(alpha_ratio, 1e-6))
            rgba_pixels[x, y] = (
                max(0, min(255, out_r)),
                max(0, min(255, out_g)),
                max(0, min(255, out_b)),
                a,
            )

    return rgba


def main() -> None:
    args = parse_args()
    input_path = Path(args.input).expanduser()
    output_path = Path(args.output).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    source = Image.open(input_path).convert("RGBA")
    samples = corner_samples(source, args.corner_size)
    matte_color = tuple(
        round(sum(channel) / len(samples)) for channel in zip(*samples)
    )

    alpha = build_background_mask(source, samples, args.threshold)
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=args.blur_radius))
    result = decontaminate_edges(source, alpha, matte_color, args.floor_alpha)
    result.save(output_path, format="PNG")


if __name__ == "__main__":
    main()
