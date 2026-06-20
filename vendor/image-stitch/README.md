# 📸 Image Stitch

[![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![OpenCV](https://img.shields.io/badge/OpenCV-4.8+-green.svg)](https://opencv.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 🧩 Seamlessly stitch multiple scrolling screenshots into a single image.

A simple yet powerful tool for combining sequential screenshots captured from scrolling content. Perfect for creating long screenshots of web pages, chat conversations, documents, and more.

## ✨ Features

- 🔄 **Automatic Overlap Detection** - Uses ORB feature matching to find and align overlapping regions
- ↕️ **Vertical Stitching** - For up/down scrolling content (default)
- ↔️ **Horizontal Stitching** - For left/right scrolling content
- 🎯 **Smart Alignment** - Corrects minor horizontal/vertical misalignment between images
- ✂️ **Auto Cropping** - Trims output to the common region across all images

## 📋 Requirements

- Python 3.10+
- opencv-python >= 4.8.0
- numpy >= 1.24.0

## 🚀 Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/skill-image-stitch.git
cd skill-image-stitch

# Create virtual environment (optional but recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## 📖 Usage

### Basic Usage

```bash
# Stitch images from a folder (vertical, sorted by filename)
python stitch.py -i input/ -o output/result.png

# Horizontal stitching
python stitch.py -i input/ -o output/result.png --horizontal

# Specify individual images
python stitch.py img1.png img2.png img3.png -o result.png
```

### Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--input` | `-i` | Input folder containing images (sorted by filename) |
| `--output` | `-o` | Output file path (default: `output/stitched.png`) |
| `--horizontal` | `-H` | Use horizontal stitching mode |
| `--no-detect` | | Disable overlap detection (direct concatenation) |
| `--debug` | | Show detailed matching information |

### Examples

```bash
# Stitch chat screenshots vertically
python stitch.py -i screenshots/chat/ -o chat_full.png

# Stitch panorama images horizontally
python stitch.py -i screenshots/panorama/ -o panorama.png -H

# Debug mode to see matching details
python stitch.py -i input/ -o output.png --debug
```

## 🔧 How It Works

```
┌─────────────┐
│   Image 1   │
│             │
│  ┌──────────┼──────────┐
│  │ Overlap  │          │
└──┼──────────┘          │
   │       Image 2       │
   │                     │
   │  ┌──────────────────┼──────────┐
   │  │     Overlap      │          │
   └──┼──────────────────┘          │
      │         Image 3             │
      │                             │
      └─────────────────────────────┘
                  ↓
      ┌─────────────────────────────┐
      │                             │
      │      Stitched Result        │
      │                             │
      └─────────────────────────────┘
```

1. **🔍 Feature Detection** - Extracts ORB keypoints from overlap regions
2. **🔗 Matching** - Finds corresponding points between consecutive images
3. **📐 Offset Calculation** - Computes overlap amount and alignment shift
4. **🖼️ Stitching** - Places images on canvas with calculated offsets
5. **✂️ Cropping** - Trims to the common visible region

## 💡 Tips for Best Results

| ✅ Do | ❌ Don't |
|-------|----------|
| Keep **20%+ overlap** between images | Use images with no overlap |
| Maintain similar dimensions | Mix very different sized images |
| Include content-rich overlap areas | Overlap on solid color regions |
| Use consistent scroll direction | Change scroll direction mid-capture |

## 📁 Project Structure

```
skill-image-stitch/
├── 📄 SKILL.md           # Skill definition for AI agents
├── 🐍 stitch.py          # Main stitching script
├── 📋 requirements.txt   # Python dependencies
├── 📖 README.md          # This file
├── 📂 input/             # Default input directory
└── 📂 output/            # Default output directory
```

## ⚠️ Limitations

- Maximum **10 images** per stitch operation
- Requires **20%+ overlap** for reliable matching
- May struggle with:
  - Pure solid color regions
  - Highly repetitive patterns
  - Very low resolution images

## 🤝 Contributing

Contributions are welcome! Feel free to:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [OpenCV](https://opencv.org/) for the powerful computer vision library
- [ORB (Oriented FAST and Rotated BRIEF)](https://docs.opencv.org/4.x/d1/d89/tutorial_py_orb.html) for feature detection

---

<p align="center">
  Made with ❤️ for seamless screenshots
</p>
