#!/usr/bin/env python3
"""Normalize host ownership to root:wheel without touching signed executable bytes."""
import gzip
import io
import lzma
from pathlib import Path, PurePosixPath
import sys
import tarfile


def main():
    path = Path(sys.argv[1])
    data = path.read_bytes()
    assert data[:8] == b"!<arch>\n"
    pos, output = 8, bytearray(data[:8])
    while pos < len(data):
        header = data[pos:pos + 60]
        assert len(header) == 60 and header[58:60] == b"`\n"
        name = header[:16].decode().strip().rstrip("/")
        size = int(header[48:58])
        content = data[pos + 60:pos + 60 + size]
        assert len(content) == size
        if name.startswith(("control.tar", "data.tar")):
            buffer = io.BytesIO()
            with tarfile.open(fileobj=io.BytesIO(content), mode="r:*") as source:
                with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as dest:
                    for item in source:
                        p = PurePosixPath(item.name)
                        assert not p.is_absolute() and ".." not in p.parts
                        marker = False
                        assert item.isfile() or item.isdir() or marker
                        item.uid = item.gid = 0
                        if p.name == "bauhelper": item.mode = 0o4755
                        item.uname, item.gname = "root", "wheel"
                        item.pax_headers = {}
                        dest.addfile(item, source.extractfile(item) if item.isfile() else None)
            raw = buffer.getvalue()
            if name.endswith(".gz"): content = gzip.compress(raw, compresslevel=9, mtime=0)
            elif name.endswith(".lzma"): content = lzma.compress(raw, format=lzma.FORMAT_ALONE)
            elif name.endswith(".xz"): content = lzma.compress(raw, format=lzma.FORMAT_XZ)
            else: raise ValueError("unsupported compression")
        new_header = header[:28] + b"0     0     " + header[40:48] + f"{len(content):<10}".encode() + b"`\n"
        assert len(new_header) == 60
        output += new_header + content
        if len(content) % 2: output += b"\n"
        pos += 60 + size + (size % 2)
    path.write_bytes(output)
    print("Normalized package ownership to root:wheel")


if __name__ == "__main__": main()
