#!/usr/bin/env python3
"""Extract the first-24-hour NUMERIC vital-sign tracks from VitalDB .vital files (stdlib only).

Usage:  python -I extract_vital_tracks.py <vital_files_dir> <out_csv> [n_workers] [window_hours]

Writes one row per (caseid, track): the first MAXKEEP valid values inside [file start, file start + window] and the
total number of values seen in the window. Time is seconds from the file (= case) start, the clock used by VitalDB's
clinical_data. Only the numeric tracks listed in WANTED are read; waveform packets are skipped.

The .vital format (gzip; 'VITA' header; typed packets) was implemented from the public format used by the open-source
`vitaldb` reader. The files are treated as untrusted input: every length is bounds-checked and a malformed file is
logged and skipped, never executed.
"""
import csv, gzip, math, os, struct, sys
from multiprocessing import Pool

WANTED = {  # full track name (device/track) -> short key
    'Solar8000/HR': 'HR', 'Solar8000/PLETH_HR': 'PLETH_HR',
    'Solar8000/ART_SBP': 'ART_SBP', 'Solar8000/ART_DBP': 'ART_DBP', 'Solar8000/ART_MBP': 'ART_MBP',
    'Solar8000/NIBP_SBP': 'NIBP_SBP', 'Solar8000/NIBP_DBP': 'NIBP_DBP', 'Solar8000/NIBP_MBP': 'NIBP_MBP',
    'Solar8000/PLETH_SPO2': 'PLETH_SPO2', 'Solar8000/RR': 'RR', 'Solar8000/RR_CO2': 'RR_CO2', 'Solar8000/BT': 'BT',
}
FMT = {1: ('f', 4), 2: ('d', 8), 3: ('b', 1), 4: ('B', 1), 5: ('h', 2), 6: ('H', 2), 7: ('l', 4), 8: ('L', 4)}
MAXKEEP = 20
U8, U16, U32, F32, F64 = (struct.Struct('<' + c).unpack_from for c in 'BHLfd')


def rstr(buf, pos):
    n = U32(buf, pos)[0]; pos += 4
    if n > len(buf) - pos:
        raise ValueError('string overruns packet')
    return buf[pos:pos + n].decode('utf-8', 'ignore'), pos + n


def parse(path, window_s):
    out = {}                                    # key -> [n, [(t, v), ...]]
    with open(path, 'rb') as raw, gzip.GzipFile(fileobj=raw) as f:
        if f.read(4) != b'VITA':
            raise ValueError('not a VITA file')
        f.read(4)
        hl = U16(f.read(2), 0)[0]
        header = f.read(hl)
        dtstart = F64(header, 10)[0] if hl >= 18 else 0.0
        dnames, trks = {}, {}                   # did -> name ; tid -> (key, fmtcode, fmtlen, gain, offset)
        t0 = dtstart if dtstart > 0 else None
        while True:
            h = f.read(5)
            if len(h) < 5:
                break
            ptype, plen = U8(h, 0)[0], U32(h, 1)[0]
            if plen > 50_000_000:
                raise ValueError('implausible packet length')
            buf = f.read(plen)
            if len(buf) < plen:
                break
            if ptype == 9:                                       # device info
                did = U32(buf, 0)[0]; dtype, p = rstr(buf, 4); name, p = rstr(buf, p)
                dnames[did] = name or dtype
            elif ptype == 0:                                     # track info
                tid = U16(buf, 0)[0]; ttype, fmt = U8(buf, 2)[0], U8(buf, 3)[0]
                tname, p = rstr(buf, 4)
                gain, offset, did = 1.0, 0.0, 0
                if len(buf) > p:
                    _, p = rstr(buf, p)                          # unit
                    p += 4 + 4 + 4 + 4                          # mindisp, maxdisp, colour, srate
                    if len(buf) >= p + 16:
                        gain, offset = F64(buf, p)[0], F64(buf, p + 8)[0]; p += 16
                        if len(buf) >= p + 5:
                            did = U32(buf, p + 1)[0]
                full = dnames.get(did, '') + '/' + tname if did in dnames else tname
                if ttype == 2 and fmt in FMT and full in WANTED:
                    trks[tid] = (WANTED[full], FMT[fmt][0], FMT[fmt][1], gain if gain else 1.0, offset)
            elif ptype == 1:                                     # record
                if len(buf) < 12:
                    continue
                infolen = U16(buf, 0)[0]; dt = F64(buf, 2)[0]; tid = U16(buf, 10)[0]
                if t0 is None and dt > 0:
                    t0 = dt
                if t0 is not None and dt - t0 > window_s + 3600:
                    break                                        # records are time-ordered: nothing relevant follows
                if tid not in trks:
                    continue
                key, code, flen, gain, offset = trks[tid]
                pos = 2 + infolen
                if len(buf) < pos + flen or t0 is None:
                    continue
                v = struct.unpack_from('<' + code, buf, pos)[0]
                t = dt - t0
                if t < 0 or t > window_s or v is None or (isinstance(v, float) and math.isnan(v)):
                    continue
                v = v * gain + offset
                e = out.setdefault(key, [0, []])
                e[0] += 1
                if len(e[1]) < MAXKEEP:
                    e[1].append((round(t, 1), v))
    return out


def work(args):
    path, window_s = args
    caseid = int(os.path.basename(path).split('.')[0])
    try:
        res = parse(path, window_s)
        return caseid, res, None
    except Exception as e:                                       # malformed file: report, skip
        return caseid, {}, f'{type(e).__name__}: {e}'


if __name__ == '__main__':
    vdir, out_csv = sys.argv[1], sys.argv[2]
    nproc = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    window_s = (float(sys.argv[4]) if len(sys.argv) > 4 else 24.0) * 3600
    files = sorted(os.path.join(vdir, x) for x in os.listdir(vdir) if x.endswith('.vital'))
    tmp = out_csv + '.tmp'
    nerr = nrow = 0
    with open(tmp, 'w', newline='', encoding='utf-8') as fh, Pool(nproc) as pool:
        w = csv.writer(fh); w.writerow(['caseid', 'track', 'n_in_window', 'time_s', 'value'])
        for i, (caseid, res, err) in enumerate(pool.imap_unordered(work, [(p, window_s) for p in files], chunksize=4), 1):
            if err:
                nerr += 1; print(f'WARN case {caseid}: {err}', file=sys.stderr)
            for key, (n, vals) in res.items():
                for t, v in vals:
                    w.writerow([caseid, key, n, t, v]); nrow += 1
            if i % 250 == 0:
                print(f'{i}/{len(files)} files, {nrow} rows, {nerr} errors', flush=True)
    os.replace(tmp, out_csv)
    print(f'done: {len(files)} files, {nrow} rows, {nerr} errors')
