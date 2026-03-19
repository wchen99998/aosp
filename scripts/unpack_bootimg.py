#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
import struct


BOOT_IMAGE_HEADER_V3_PAGESIZE = 4096
VENDOR_RAMDISK_NAME_SIZE = 32
VENDOR_RAMDISK_TABLE_ENTRY_BOARD_ID_SIZE = 16


def page_count(size: int, page_size: int) -> int:
    return (size + page_size - 1) // page_size


def extract_image(image_file, offset: int, size: int, destination: Path) -> None:
    image_file.seek(offset)
    destination.write_bytes(image_file.read(size))


def unpack_boot_image(image_file, output_dir: Path) -> None:
    image_file.seek(8)
    header_words = struct.unpack("9I", image_file.read(9 * 4))
    header_version = header_words[8]

    kernel_size = header_words[0]
    ramdisk_size = header_words[1] if header_version >= 3 else header_words[2]
    page_size = BOOT_IMAGE_HEADER_V3_PAGESIZE if header_version >= 3 else header_words[7]

    kernel_offset = page_size
    ramdisk_offset = page_size * (1 + page_count(kernel_size, page_size))

    extract_image(image_file, kernel_offset, kernel_size, output_dir / "kernel")
    extract_image(image_file, ramdisk_offset, ramdisk_size, output_dir / "ramdisk")


def unpack_vendor_boot_image(image_file, output_dir: Path) -> None:
    image_file.seek(8)
    header_version = struct.unpack("I", image_file.read(4))[0]
    page_size = struct.unpack("I", image_file.read(4))[0]
    image_file.read(4)  # kernel load address
    image_file.read(4)  # ramdisk load address
    vendor_ramdisk_size = struct.unpack("I", image_file.read(4))[0]
    image_file.read(2048)  # cmdline
    image_file.read(4)  # tags load address
    image_file.read(16)  # product name
    header_size = struct.unpack("I", image_file.read(4))[0]
    dtb_size = struct.unpack("I", image_file.read(4))[0]
    image_file.read(8)  # dtb load address

    num_header_pages = page_count(header_size, page_size)
    num_ramdisk_pages = page_count(vendor_ramdisk_size, page_size)
    num_dtb_pages = page_count(dtb_size, page_size)
    ramdisk_offset_base = page_size * num_header_pages
    dtb_offset = page_size * (num_header_pages + num_ramdisk_pages)

    if header_version > 3:
        vendor_ramdisk_table_size = struct.unpack("I", image_file.read(4))[0]
        vendor_ramdisk_table_entry_num = struct.unpack("I", image_file.read(4))[0]
        vendor_ramdisk_table_entry_size = struct.unpack("I", image_file.read(4))[0]
        vendor_bootconfig_size = struct.unpack("I", image_file.read(4))[0]
        num_vendor_ramdisk_table_pages = page_count(vendor_ramdisk_table_size, page_size)
        vendor_ramdisk_table_offset = page_size * (
            num_header_pages + num_ramdisk_pages + num_dtb_pages
        )

        for index in range(vendor_ramdisk_table_entry_num):
            entry_offset = vendor_ramdisk_table_offset + (vendor_ramdisk_table_entry_size * index)
            image_file.seek(entry_offset)
            ramdisk_size = struct.unpack("I", image_file.read(4))[0]
            ramdisk_offset = struct.unpack("I", image_file.read(4))[0]
            image_file.read(4)  # ramdisk type
            image_file.read(VENDOR_RAMDISK_NAME_SIZE)
            image_file.read(4 * VENDOR_RAMDISK_TABLE_ENTRY_BOARD_ID_SIZE)
            extract_image(
                image_file,
                ramdisk_offset_base + ramdisk_offset,
                ramdisk_size,
                output_dir / f"vendor_ramdisk{index:02}",
            )

        bootconfig_offset = page_size * (
            num_header_pages + num_ramdisk_pages + num_dtb_pages + num_vendor_ramdisk_table_pages
        )
        extract_image(image_file, bootconfig_offset, vendor_bootconfig_size, output_dir / "bootconfig")
    else:
        extract_image(
            image_file,
            ramdisk_offset_base,
            vendor_ramdisk_size,
            output_dir / "vendor_ramdisk",
        )

    if dtb_size > 0:
        extract_image(image_file, dtb_offset, dtb_size, output_dir / "dtb")


def unpack_bootimg(boot_image_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    with boot_image_path.open("rb") as image_file:
        magic = image_file.read(8)
        image_file.seek(0)

        if magic == b"ANDROID!":
            unpack_boot_image(image_file, output_dir)
            return

        if magic == b"VNDRBOOT":
            unpack_vendor_boot_image(image_file, output_dir)
            return

        raise ValueError(f"Unsupported boot image magic: {magic!r}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Unpack Android boot/vendor_boot images.")
    parser.add_argument("--boot_img", required=True, help="Path to boot.img or vendor_boot.img")
    parser.add_argument("--out", required=True, help="Output directory")
    args = parser.parse_args()

    unpack_bootimg(Path(args.boot_img), Path(args.out))


if __name__ == "__main__":
    main()
