"""Mersin ürün tablosunu (xlsx) app/assets/crops.json dosyasına çevirir.
Kullanım: python3 xlsx_to_json.py tablo.xlsx ../app/assets/crops.json"""
import json, re, sys
import openpyxl

FIX = {"BOYZAZI": "BOZYAZI"}  # yazım düzeltmeleri

def _cap(s):
    out = []
    for w in s.split():
        first = w[0]
        first = "İ" if first == "i" else ("I" if first == "ı" else first.upper())
        out.append(first + w[1:])
    return " ".join(out)

def parse_crop(raw):
    raw = re.sub(r"\s+", " ", raw.strip())
    m = re.match(r"^(.*?)\s*\((.*)\)$", raw)
    if not m:
        return {"name": _cap(raw.replace("I", "ı").replace("İ", "i").lower()), "variant": None}
    base, inner = m.group(1), m.group(2).strip()
    low = lambda t: t.replace("I", "ı").replace("İ", "i").lower()
    return {"name": _cap(low(base)), "variant": _cap(low(inner)) if inner else None}

def main(src, dst):
    ws = openpyxl.load_workbook(src, data_only=True).active
    rows = list(ws.iter_rows(values_only=True))
    districts = {}
    for ci, head in enumerate(rows[0]):
        if not head:
            continue
        h = FIX.get(head.strip().upper(), head.strip().upper())
        low = h.replace("I", "ı").replace("İ", "i").lower()
        name = _cap(low)
        crops, seen = [], set()
        for r in rows[1:]:
            v = r[ci] if ci < len(r) else None
            if not v or not str(v).strip():
                continue
            c = parse_crop(str(v))
            key = (c["name"], c["variant"])
            if key in seen:
                continue
            seen.add(key)
            c["label"] = c["name"] + (f" ({c['variant']})" if c["variant"] else "")
            crops.append(c)
        districts[name] = crops
    json.dump({"province": "Mersin", "districts": districts}, open(dst, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print({k: len(v) for k, v in districts.items()})

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
