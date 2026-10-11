"""Extract numericitems.csv from the AmsterdamUMCdb v1.0.2 download (`numericitems.zip`).

Why this script exists: the distributed file is a zip whose single entry (`numericitems.zip`) is compressed with
Deflate64 (zip method 9) and itself contains `numericitems.csv` as an ordinary deflate zip. Common tools do not
read Deflate64 (Python's zipfile, bsdtar), and the 7-Zip route needs the whole file on disk twice.
This script streams outer (Deflate64) -> inner (deflate) -> CSV in constant memory.

Safety: the output is written to `<out>.part` and renamed to `<out>` ONLY when the inner deflate stream ended
cleanly AND its CRC-32 matches the value stored in the zip. A truncated download therefore never yields a
numericitems.csv that the pipeline could silently analyse.

Usage (stdlib + `pip install inflate64`; run isolated):
    python -I extract_numericitems.py <path/to/numericitems.zip> <out/numericitems.csv>
    # code-development smoke test on a truncated file only (output named *_PARTIAL_smoketest.csv, never used by the pipeline):
    python -I extract_numericitems.py <zip> <out/numericitems.csv> --partial-gb 2
"""
import os
import struct
import sys
import zlib


def main(argv):
    argv = list(argv)
    partial_gb = None
    if "--partial-gb" in argv:
        i = argv.index("--partial-gb")
        partial_gb = float(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) != 2:
        print(__doc__)
        return 2
    src, out = argv
    if partial_gb:
        out = os.path.splitext(out)[0] + "_PARTIAL_smoketest.csv"
    try:
        import inflate64
    except ImportError:
        print("ERROR: the 'inflate64' package is required (pip install inflate64).")
        return 2

    fh = open(src, "rb")
    hdr = fh.read(30)
    if hdr[:4] != b"PK\x03\x04":
        print("ERROR: not a zip file (no local header at offset 0).")
        return 1
    method = struct.unpack("<H", hdr[8:10])[0]
    n, m = struct.unpack("<HH", hdr[26:30])
    print("outer entry:", fh.read(n).decode("latin-1"), "| method", method)
    fh.read(m)
    if method != 9:
        print("ERROR: outer entry is not Deflate64 (method %d); extract it with any zip tool instead." % method)
        return 1

    inflater = inflate64.Inflater()
    buf = b""
    inner_started = False
    dec = None
    crc = 0
    written = 0
    tail = b""
    done = False
    limit = int(partial_gb * (1 << 30)) if partial_gb else None
    part = out + ".part"
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    err = None
    inner_crc_hdr = None
    with open(part, "wb") as fo:
        try:
            while True:
                chunk = fh.read(1 << 24)
                if not chunk:
                    break
                data = inflater.inflate(chunk)
                if done:                                  # collecting the data descriptor after the CSV
                    tail += data
                    if len(tail) >= 16:
                        break
                    continue
                if not inner_started:
                    buf += data
                    if len(buf) < 30:
                        continue
                    if buf[:4] != b"PK\x03\x04":
                        raise ValueError("inner stream is not a zip local header")
                    flags, meth2 = struct.unpack("<HH", buf[6:10])
                    inner_crc_hdr = struct.unpack("<I", buf[14:18])[0] if not flags & 8 else None
                    n2, m2 = struct.unpack("<HH", buf[26:30])
                    name = buf[30:30 + n2].decode("latin-1")
                    print("inner entry:", name, "| method", meth2)
                    if os.path.basename(name).lower() != "numericitems.csv" or meth2 != 8:
                        raise ValueError("unexpected inner entry (expected deflate 'numericitems.csv')")
                    data = buf[30 + n2 + m2:]
                    inner_started = True
                    dec = zlib.decompressobj(-15)
                out_b = dec.decompress(data)
                fo.write(out_b)
                crc = zlib.crc32(out_b, crc)
                written += len(out_b)
                if dec.eof:
                    done = True
                    tail = dec.unused_data
                    if len(tail) >= 16 or inner_crc_hdr is not None:
                        break
                if limit and written >= limit:
                    break
        except Exception as e:  # truncated / corrupt input surfaces here (zlib.error, inflate64 errors, ValueError)
            err = "%s: %s" % (type(e).__name__, e)

    print("csv bytes written: %d" % written)
    if limit and err is None and not done:
        print("PARTIAL smoke-test file written (NOT a valid extraction): %s" % out)
        os.replace(part, out)
        return 0
    if err or not done:
        print("FAILED: the zip is truncated or corrupt (%s). Nothing was published; re-download the file." % (err or "stream ended before the CSV was complete"))
        os.remove(part)
        return 1
    if inner_crc_hdr is not None:
        want = inner_crc_hdr
    else:
        off = 4 if tail[:4] == b"PK\x07\x08" else 0
        want = struct.unpack("<I", tail[off:off + 4])[0]
    if (crc & 0xFFFFFFFF) != want:
        print("FAILED: CRC-32 mismatch (computed %08x, stored %08x). Nothing was published." % (crc & 0xFFFFFFFF, want))
        os.remove(part)
        return 1
    os.replace(part, out)
    print("OK: %s (%d bytes, CRC-32 verified)" % (out, written))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
