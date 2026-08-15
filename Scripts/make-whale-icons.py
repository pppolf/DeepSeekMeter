"""生成鲸鱼娘图标资源：圆形裁剪（圆外透明）+ 多尺寸 ICO。

本脚本仅用于重新生成图标；应用构建和运行不依赖本脚本，也不依赖 Pillow。
用法：
  python Scripts/make-whale-icons.py --main <主图png> --tray <简化图png>
可选：
  --out-dir <输出目录，默认 windows/assets>
  --ico <输出 ico 路径，默认 windows/src/DeepSeekMeter/app.ico>

注意：不会覆盖输入的源图片。
"""
import argparse
import io
import os
import struct
import sys


def circular_crop(src, out, size=512):
    """圆形裁剪：以中心为圆，圆外透明（4x 超采样抗锯齿）。"""
    from PIL import Image, ImageDraw
    im = Image.open(src).convert("RGBA")
    im = im.resize((size * 4, size * 4), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    im.putalpha(mask)
    im = im.resize((size, size), Image.LANCZOS)
    im.save(out)
    return im


def png_bytes(im, size):
    from PIL import Image
    buf = im.resize((size, size), Image.LANCZOS)
    b = io.BytesIO()
    buf.save(b, "PNG")
    return b.getvalue()


def make_ico(pngs, out):
    entries = []
    offset = 6 + 16 * len(pngs)
    datas = []
    for size, data in pngs:
        w = 0 if size >= 256 else size
        h = 0 if size >= 256 else size
        entries.append(struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(data), offset))
        datas.append(data)
        offset += len(data)
    header = struct.pack("<HHH", 0, 1, len(pngs))
    with open(out, "wb") as f:
        f.write(header)
        for e in entries:
            f.write(e)
        for d in datas:
            f.write(d)


def main():
    parser = argparse.ArgumentParser(description="生成鲸鱼娘图标（圆形裁剪 + 多尺寸 ICO），仅用于重新生成图标。")
    parser.add_argument("--main", required=True, help="主应用图标源 PNG（蓝发鲸鱼娘主图）")
    parser.add_argument("--tray", required=True, help="简化托盘图标源 PNG（蓝发鲸鱼娘简化图）")
    parser.add_argument("--out-dir", default=None, help="PNG 输出目录（默认 windows/assets）")
    parser.add_argument("--ico", default=None, help="ICO 输出路径（默认 windows/src/DeepSeekMeter/app.ico）")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = args.out_dir or os.path.join(root, "windows", "assets")
    ico_out = args.ico or os.path.join(root, "windows", "src", "DeepSeekMeter", "app.ico")

    for path, name in [(args.main, "主图"), (args.tray, "简化图")]:
        if not os.path.isfile(path):
            print(f"错误：找不到输入图片（{name}）：{path}", file=sys.stderr)
            sys.exit(2)

    # 防御：避免输入输出为同一文件（不覆盖源文件）
    main_png = os.path.join(out_dir, "whale-girl-main.png")
    tray_png = os.path.join(out_dir, "whale-girl-tray.png")
    for src, dst in [(args.main, main_png), (args.tray, tray_png)]:
        if os.path.abspath(src) == os.path.abspath(dst):
            print(f"错误：输入与输出路径相同，拒绝覆盖源文件：{src}", file=sys.stderr)
            sys.exit(2)

    os.makedirs(out_dir, exist_ok=True)

    print("圆形裁剪主图…")
    main_im = circular_crop(args.main, main_png, 512)
    print("圆形裁剪简化图…")
    circular_crop(args.tray, tray_png, 512)

    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    pngs = [(s, png_bytes(main_im, s)) for s in sizes]
    make_ico(pngs, ico_out)
    print(f"已生成：{main_png}")
    print(f"已生成：{tray_png}")
    print(f"已生成 ICO：{ico_out}（{len(sizes)} 个尺寸）")


if __name__ == "__main__":
    main()
