"""Kayıtların özetini çıkarır: kaç kayıt, hangi ürün/hastalık, model ne kadar doğru.
Kullanım (server klasöründe):  python3 ozet.py"""
import json, sqlite3
from collections import Counter, defaultdict
from pathlib import Path

db = Path(__file__).parent / "data" / "kayitlar.db"
if not db.exists():
    raise SystemExit("Henüz kayıt yok (data/kayitlar.db bulunamadı).")
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
rows = [dict(r) for r in con.execute("SELECT * FROM records ORDER BY created_at")]
real = [r for r in rows if not r["demo"]]
print(f"Toplam kayıt: {len(rows)}  (gerçek analiz: {len(real)}, demo: {len(rows) - len(real)})")

rated = [r for r in real if r["verdict"]]
print(f"Değerlendirilen: {len(rated)}   değerlendirilmeyen: {len(real) - len(rated)}")
if not real:
    raise SystemExit

c = Counter(r["verdict"] for r in rated)
print(f"  Doğru: {c['dogru']}   Yanlış: {c['yanlis']}   Emin değilim: {c['belirsiz']}")
sure = c["dogru"] + c["yanlis"]
if sure:
    print(f"  Modelin ilk teşhis doğruluğu (emin olunanlar): %{100 * c['dogru'] / sure:.0f}  ({c['dogru']}/{sure})")

print("\nÜrün bazında (doğru / değerlendirilen):")
by = defaultdict(lambda: [0, 0, 0])  # kayıt, dogru, yanlis
for r in real:
    name = r["crop"] + (f" ({r['variant']})" if r["variant"] else "")
    by[name][0] += 1
    if r["verdict"] == "dogru": by[name][1] += 1
    if r["verdict"] == "yanlis": by[name][2] += 1
for k, (n, d, y) in sorted(by.items(), key=lambda x: -x[1][0]):
    print(f"  {k:28s} kayıt {n:3d}   doğru {d:3d}   yanlış {y:3d}")

print("\nUzmanın verdiği doğru teşhisler (etiketli veri):")
labels = Counter(
    (r["crop"], (r["correct_diagnosis"] or "").strip().lower())
    for r in rated if r["verdict"] == "yanlis" and r["correct_diagnosis"])
for (crop, lab), n in labels.most_common():
    print(f"  {crop:20s} {lab:35s} {n}")

print("\nYanlış bulunan vakalar (modelin ilk teşhisi → uzmanın teşhisi):")
for r in rated:
    if r["verdict"] == "yanlis":
        t = (json.loads(r["ai_json"]).get("teshisler") or [{}])[0]
        print(f"  {r['id']}  {r['crop']}: {t.get('ad', '?')} → {r['correct_diagnosis']}")
