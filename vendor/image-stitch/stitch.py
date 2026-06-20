#!/usr/bin/env python3
"""
Screenshot Stitch Tool - Stitch scrolling screenshots vertically or horizontally.

Uses ORB feature matching to find alignment offsets.
"""

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np


def find_offset_vertical(
    img1: np.ndarray,
    img2: np.ndarray,
    debug: bool = False,
) -> tuple[int, int]:
    """
    Find offset for vertical stitching (img2 below img1).

    Returns:
        (dx, overlap_y): Horizontal shift and vertical overlap
    """
    h1, w1 = img1.shape[:2]
    h2, w2 = img2.shape[:2]

    orb = cv2.ORB_create(nfeatures=2000)
    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    edge_h = min(150, h1 // 4, h2 // 4)
    region1 = img1[h1 - edge_h : h1, :]  # img1 bottom
    region2 = img2[:edge_h, :]  # img2 top

    gray1 = cv2.cvtColor(region1, cv2.COLOR_BGR2GRAY)
    gray2 = cv2.cvtColor(region2, cv2.COLOR_BGR2GRAY)

    kp1, des1 = orb.detectAndCompute(gray1, None)
    kp2, des2 = orb.detectAndCompute(gray2, None)

    if des1 is None or des2 is None or len(kp1) < 10 or len(kp2) < 10:
        if debug:
            print("    Too few features")
        return 0, 0

    matches = bf.match(des1, des2)
    matches = sorted(matches, key=lambda x: x.distance)[:30]

    if len(matches) < 5:
        if debug:
            print(f"    Too few matches: {len(matches)}")
        return 0, 0

    dx_list = []
    overlap_list = []
    for m in matches:
        x1, y1 = kp1[m.queryIdx].pt
        x2, y2 = kp2[m.trainIdx].pt
        dx_list.append(x2 - x1)
        overlap_list.append((edge_h - y1) + y2)

    dx = -int(np.median(dx_list))  # Negate: offset vs position
    overlap = int(np.median(overlap_list))

    if debug:
        print(f"    Matches: {len(matches)}, dx={dx}, overlap_y={overlap}")

    return dx, max(0, overlap)


def find_offset_horizontal(
    img1: np.ndarray,
    img2: np.ndarray,
    debug: bool = False,
) -> tuple[int, int]:
    """
    Find offset for horizontal stitching (img2 right of img1).

    Returns:
        (dy, overlap_x): Vertical shift and horizontal overlap
    """
    h1, w1 = img1.shape[:2]
    h2, w2 = img2.shape[:2]

    orb = cv2.ORB_create(nfeatures=2000)
    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    edge_w = min(150, w1 // 4, w2 // 4)
    region1 = img1[:, w1 - edge_w : w1]  # img1 right
    region2 = img2[:, :edge_w]  # img2 left

    gray1 = cv2.cvtColor(region1, cv2.COLOR_BGR2GRAY)
    gray2 = cv2.cvtColor(region2, cv2.COLOR_BGR2GRAY)

    kp1, des1 = orb.detectAndCompute(gray1, None)
    kp2, des2 = orb.detectAndCompute(gray2, None)

    if des1 is None or des2 is None or len(kp1) < 10 or len(kp2) < 10:
        if debug:
            print("    Too few features")
        return 0, 0

    matches = bf.match(des1, des2)
    matches = sorted(matches, key=lambda x: x.distance)[:30]

    if len(matches) < 5:
        if debug:
            print(f"    Too few matches: {len(matches)}")
        return 0, 0

    dy_list = []
    overlap_list = []
    for m in matches:
        x1, y1 = kp1[m.queryIdx].pt
        x2, y2 = kp2[m.trainIdx].pt
        dy_list.append(y2 - y1)
        overlap_list.append((edge_w - x1) + x2)

    dy = -int(np.median(dy_list))  # Negate: offset vs position
    overlap = int(np.median(overlap_list))

    if debug:
        print(f"    Matches: {len(matches)}, dy={dy}, overlap_x={overlap}")

    return dy, max(0, overlap)


def stitch_screenshots(
    image_paths: list,
    output_path: str,
    direction: str = "vertical",
    detect_overlap: bool = True,
    debug: bool = False,
) -> bool:
    """
    Stitch multiple screenshots.

    Args:
        image_paths: List of image paths (in order)
        output_path: Output file path
        direction: "vertical" (default) or "horizontal"
        detect_overlap: Auto-detect overlap
        debug: Print debug info

    Returns:
        True if successful
    """
    if not image_paths:
        print("No images provided")
        return False

    if len(image_paths) > 10:
        print("Maximum 10 images allowed")
        return False

    # Load images
    images = []
    for path in image_paths:
        img = cv2.imread(str(path))
        if img is None:
            print(f"Failed to load: {path}")
            return False
        images.append(img)
        print(f"Loaded: {path} ({img.shape[1]}x{img.shape[0]})")

    if len(images) == 1:
        cv2.imwrite(str(output_path), images[0])
        print(f"Saved: {output_path}")
        return True

    is_horizontal = direction == "horizontal"
    find_offset = find_offset_horizontal if is_horizontal else find_offset_vertical

    # Find offsets between consecutive images
    offsets = []
    print()
    for i in range(len(images) - 1):
        if detect_overlap:
            if debug:
                print(f"Finding offset {i + 1} -> {i + 2}:")
            offset, overlap = find_offset(images[i], images[i + 1], debug=debug)
            if is_horizontal:
                print(f"Image {i + 1} -> {i + 2}: dy={offset}, overlap_x={overlap}px")
            else:
                print(f"Image {i + 1} -> {i + 2}: dx={offset}, overlap_y={overlap}px")
            offsets.append((offset, overlap))
        else:
            offsets.append((0, 0))

    # Calculate global positions
    positions = [(0, 0)]
    for i, (offset, overlap) in enumerate(offsets):
        prev_x, prev_y = positions[-1]
        h, w = images[i].shape[:2]

        if is_horizontal:
            # Horizontal: move right (x), adjust vertical (y)
            new_x = prev_x + w - overlap
            new_y = prev_y + offset
        else:
            # Vertical: move down (y), adjust horizontal (x)
            new_x = prev_x + offset
            new_y = prev_y + h - overlap

        positions.append((new_x, new_y))

    if debug:
        print(f"\nPositions: {positions}")

    # Calculate canvas dimensions
    min_x = min(p[0] for p in positions)
    min_y = min(p[1] for p in positions)
    max_x = max(positions[i][0] + images[i].shape[1] for i in range(len(images)))
    max_y = max(positions[i][1] + images[i].shape[0] for i in range(len(images)))

    canvas_w = max_x - min_x
    canvas_h = max_y - min_y

    print(f"\nCanvas: {canvas_w}x{canvas_h}")

    # Create canvas and place images
    canvas = np.zeros((canvas_h, canvas_w, 3), dtype=np.uint8)

    for i, (img, (px, py)) in enumerate(zip(images, positions)):
        h, w = img.shape[:2]
        x = px - min_x
        y = py - min_y
        canvas[y : y + h, x : x + w] = img

    # Crop to common region
    if is_horizontal:
        # Crop top/bottom to common height
        top = max(p[1] - min_y for p in positions)
        bottom = min(
            positions[i][1] - min_y + images[i].shape[0] for i in range(len(images))
        )
        if bottom > top:
            final = canvas[top:bottom, :]
            if debug:
                print(f"Cropped: top={top}, bottom={bottom}")
        else:
            final = canvas
    else:
        # Crop left/right to common width
        left = max(p[0] - min_x for p in positions)
        right = min(
            positions[i][0] - min_x + images[i].shape[1] for i in range(len(images))
        )
        if right > left:
            final = canvas[:, left:right]
            if debug:
                print(f"Cropped: left={left}, right={right}")
        else:
            final = canvas

    # Save
    output_dir = Path(output_path).parent
    output_dir.mkdir(parents=True, exist_ok=True)

    success = cv2.imwrite(str(output_path), final)
    if success:
        print(f"\nSaved: {output_path} ({final.shape[1]}x{final.shape[0]})")
    else:
        print(f"\nFailed to save: {output_path}")

    return success


def main():
    parser = argparse.ArgumentParser(
        description="Stitch scrolling screenshots",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python stitch.py -i input -o output/result.png
  python stitch.py -i input -o output/result.png --horizontal
  python stitch.py img1.png img2.png -o result.png
  python stitch.py --debug -i input -o result.png
        """,
    )

    parser.add_argument("images", nargs="*", help="Image paths (max 10)")
    parser.add_argument("-i", "--input", help="Input folder (sorted by filename)")
    parser.add_argument(
        "-o", "--output", default="output/stitched.png", help="Output path"
    )
    parser.add_argument(
        "--horizontal",
        "-H",
        action="store_true",
        help="Horizontal stitching (default: vertical)",
    )
    parser.add_argument(
        "--no-detect", action="store_true", help="Disable overlap detection"
    )
    parser.add_argument("--debug", action="store_true", help="Show debug info")

    args = parser.parse_args()

    image_paths = []
    if args.images:
        image_paths = [Path(p) for p in args.images]
    elif args.input:
        input_dir = Path(args.input)
        if not input_dir.is_dir():
            print(f"Input folder not found: {args.input}")
            sys.exit(1)
        extensions = {".png", ".jpg", ".jpeg", ".bmp", ".tiff", ".webp"}
        image_paths = sorted(
            [p for p in input_dir.iterdir() if p.suffix.lower() in extensions]
        )
        if not image_paths:
            print(f"No images found in: {args.input}")
            sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)

    if len(image_paths) > 10:
        print(f"Too many images ({len(image_paths)}). Maximum is 10.")
        sys.exit(1)

    direction = "horizontal" if args.horizontal else "vertical"
    print(f"Stitching {len(image_paths)} images ({direction})...\n")

    success = stitch_screenshots(
        image_paths=image_paths,
        output_path=args.output,
        direction=direction,
        detect_overlap=not args.no_detect,
        debug=args.debug,
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
