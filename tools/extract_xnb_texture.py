"""Extract uncompressed XNA/MonoGame Texture2D XNB files to lossless PNG.

This project-local utility is intentionally small and read-only with respect to
the source XNB. It preserves native pixel dimensions and writes only the first
(full-resolution) mip level.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import asdict, dataclass
from pathlib import Path

from PIL import Image


@dataclass
class TextureInfo:
    source: str
    output: str
    width: int
    height: int
    surface_format: int
    mip_count: int


class XnbReader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.offset = 0

    def read(self, size: int) -> bytes:
        end = self.offset + size
        if end > len(self.data):
            raise ValueError("Unexpected end of XNB data")
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def uint8(self) -> int:
        return self.read(1)[0]

    def int32(self) -> int:
        return struct.unpack("<i", self.read(4))[0]

    def uint32(self) -> int:
        return struct.unpack("<I", self.read(4))[0]

    def seven_bit_int(self) -> int:
        value = 0
        shift = 0
        while True:
            byte = self.uint8()
            value |= (byte & 0x7F) << shift
            if byte & 0x80 == 0:
                return value
            shift += 7
            if shift > 35:
                raise ValueError("Invalid 7-bit integer")

    def string(self) -> str:
        return self.read(self.seven_bit_int()).decode("utf-8")


def parse_texture(path: Path) -> tuple[TextureInfo, Image.Image]:
    reader = XnbReader(path.read_bytes())
    if reader.read(3) != b"XNB":
        raise ValueError("Not an XNB file")
    platform = reader.read(1)
    version = reader.uint8()
    flags = reader.uint8()
    declared_size = reader.uint32()
    if flags & 0xC0:
        raise ValueError("Compressed XNB is not supported by this extractor")
    if declared_size != len(reader.data):
        raise ValueError(f"Declared size {declared_size} differs from file size {len(reader.data)}")

    reader_count = reader.seven_bit_int()
    type_readers: list[str] = []
    for _ in range(reader_count):
        type_readers.append(reader.string())
        reader.int32()  # reader version
    reader.seven_bit_int()  # shared resource count
    primary_reader_index = reader.seven_bit_int()
    if primary_reader_index < 1 or primary_reader_index > len(type_readers):
        raise ValueError("Invalid primary type reader index")
    primary_reader = type_readers[primary_reader_index - 1]
    if "Texture2DReader" not in primary_reader:
        raise ValueError(f"Primary asset is not Texture2D: {primary_reader}")

    surface_format = reader.int32()
    width = reader.int32()
    height = reader.int32()
    mip_count = reader.int32()
    if width <= 0 or height <= 0 or mip_count <= 0:
        raise ValueError("Invalid Texture2D dimensions or mip count")

    mip_size = reader.int32()
    pixels = reader.read(mip_size)
    if surface_format == 0:  # XNA SurfaceFormat.Color, RGBA8
        expected_size = width * height * 4
        if mip_size != expected_size:
            raise ValueError(f"RGBA byte count {mip_size} != {expected_size}")
        image = Image.frombytes("RGBA", (width, height), pixels)
    elif surface_format == 12:  # Alpha8
        expected_size = width * height
        if mip_size != expected_size:
            raise ValueError(f"Alpha byte count {mip_size} != {expected_size}")
        alpha = Image.frombytes("L", (width, height), pixels)
        image = Image.new("RGBA", (width, height), (255, 255, 255, 0))
        image.putalpha(alpha)
    else:
        raise ValueError(f"Unsupported SurfaceFormat {surface_format}")

    info = TextureInfo(
        source=str(path),
        output="",
        width=width,
        height=height,
        surface_format=surface_format,
        mip_count=mip_count,
    )
    return info, image


def extract_file(source: Path, destination: Path) -> TextureInfo:
    info, image = parse_texture(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="PNG", optimize=False)
    info.output = str(destination)
    return info


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="XNB file or directory")
    parser.add_argument("destination", type=Path, help="PNG file or output directory")
    parser.add_argument("--recursive", action="store_true")
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()

    sources = [args.source]
    if args.source.is_dir():
        pattern = "**/*.xnb" if args.recursive else "*.xnb"
        sources = sorted(args.source.glob(pattern))

    results: list[dict[str, object]] = []
    failures: list[dict[str, str]] = []
    for source in sources:
        if args.source.is_dir():
            relative = source.relative_to(args.source).with_suffix(".png")
            destination = args.destination / relative
        else:
            destination = args.destination
        try:
            results.append(asdict(extract_file(source, destination)))
        except Exception as error:  # report non-texture XNBs without stopping the batch
            failures.append({"source": str(source), "error": str(error)})

    payload = {"textures": results, "failures": failures}
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"extracted": len(results), "failed": len(failures)}, ensure_ascii=False))
    return 0 if results else 1


if __name__ == "__main__":
    raise SystemExit(main())
