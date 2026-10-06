"""Bitki Asistanı sunucusu.
Çalıştırma:  uvicorn main:app --host 0.0.0.0 --port 8000
"""
import base64, csv, io, json, os, sqlite3, uuid
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import PlainTextResponse
from PIL import Image, ImageOps

load_dotenv()
BASE = Path(__file__).parent
DATA = BASE / "data"
PHOTOS = DATA / "photos"
PHOTOS.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA / "kayitlar.db"

API_KEY = os.getenv("ANTHROPIC_API_KEY", "").strip()
MODEL = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5-5").strip()
APP_TOKEN = os.getenv("APP_TOKEN", "").strip()
MAX_PHOTOS = 4
API_MAX_SIDE = 1568  # API'ye giden kopya bu boyuta küçültülür, orijinal diskte kalır

client = None
if API_KEY:
    import anthropic
    client = anthropic.Anthropic(api_key=API_KEY)

app = FastAPI(title="Bitki Asistanı")


def db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def init_db():
    with db() as con:
        con.execute("""CREATE TABLE IF NOT EXISTS records (
            id TEXT PRIMARY KEY, created_at TEXT, district TEXT, crop TEXT,
            variant TEXT, note TEXT, photos TEXT, ai_json TEXT, demo INTEGER,
            verdict TEXT, correct_diagnosis TEXT, fb_note TEXT, fb_at TEXT)""")


init_db()


def check_token(token):
    if APP_TOKEN and token != APP_TOKEN:
        raise HTTPException(401, "Geçersiz uygulama anahtarı")


SYSTEM = """Sen Türkiye'de çalışan deneyimli bir ziraat mühendisinin yardımcı asistanısın.
Sana bir bitkinin fotoğraf(lar)ı, bölge (Mersin ilçesi) ve ürün bilgisi verilir.
Görevin görselden olası bitki sağlığı sorunlarını değerlendirmektir.

Kurallar:
- Kesin hüküm verme; en olası en fazla 3 ihtimali, olasılık sırasıyla ver.
- Sadece fotoğrafta gerçekten görebildiğin belirtilere dayan; görmediğin şeyi uydurma.
- Bitki sağlıklı görünüyorsa bunu söyle ("saglikli").
- Fotoğraf bulanık, uzak, karanlık ya da yetersizse bunu belirt ve hangi ek fotoğrafın işe yarayacağını yaz.
- Fotoğraftaki bitki bildirilen ürünle uyuşmuyorsa bunu uyar.
- Öneriler kısa ve pratik olsun. Kimyasal ilaç dozu veya ticari ürün adı verme; etken madde sınıfı ya da kültürel önlem düzeyinde kal.
- Mersin'in iklimi (sıcak, nemli kıyı; seracılık; narenciye, muz, sebze) bağlamını göz önünde tut.

Cevabı SADECE aşağıdaki JSON biçiminde ver, başka metin ekleme:
{
 "urun_uyumu": {"uyumlu": true, "not": "kısa not"},
 "foto_kalitesi": {"yeterli": true, "not": "kısa not", "ek_foto_onerisi": "varsa"},
 "gozlenen_belirtiler": ["madde", "madde"],
 "teshisler": [
   {"ad": "olası sorun", "tur": "hastalik|zararli|besin_eksikligi|fizyolojik|saglikli|belirsiz",
    "guven": 0-100 arası tam sayı, "gerekce": "görseldeki dayanak", "oneri": "kısa öneri"}
 ],
 "acil": false
}
Metinler Türkçe olsun."""


def prepare_for_api(raw: bytes) -> str:
    img = Image.open(io.BytesIO(raw))
    img = ImageOps.exif_transpose(img).convert("RGB")
    img.thumbnail((API_MAX_SIDE, API_MAX_SIDE))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=85)
    return base64.standard_b64encode(buf.getvalue()).decode()


def parse_json(text: str):
    a, b = text.find("{"), text.rfind("}")
    if a == -1 or b == -1:
        raise ValueError("JSON bulunamadı")
    return json.loads(text[a:b + 1])


def demo_result(crop):
    return {
        "urun_uyumu": {"uyumlu": True, "not": "DEMO modu: gerçek analiz yapılmadı."},
        "foto_kalitesi": {"yeterli": True, "not": "DEMO", "ek_foto_onerisi": ""},
        "gozlenen_belirtiler": ["(demo) Yaprakta sarı-kahverengi lekeler"],
        "teshisler": [
            {"ad": "Yaprak leke hastalığı (demo)", "tur": "hastalik", "guven": 55,
             "gerekce": "Bu sonuç sahte; ANTHROPIC_API_KEY girilince gerçek analiz gelir.",
             "oneri": "Gerçek analiz için sunucuya API anahtarı ekleyin."},
            {"ad": "Besin eksikliği (demo)", "tur": "besin_eksikligi", "guven": 25,
             "gerekce": "Demo", "oneri": "Demo"},
        ],
        "acil": False,
    }


def analyze_with_model(images_b64, district, crop_label, note):
    content = []
    for i, b64 in enumerate(images_b64, 1):
        content.append({"type": "text", "text": f"Fotoğraf {i}:"})
        content.append({"type": "image",
                        "source": {"type": "base64", "media_type": "image/jpeg", "data": b64}})
    ask = f"İlçe: {district}, Mersin\nÜrün: {crop_label}\n"
    if note:
        ask += f"Üreticinin notu: {note}\n"
    ask += "\nBu bitkiyi değerlendir ve yalnızca istenen JSON'u döndür."
    content.append({"type": "text", "text": ask})
    resp = client.messages.create(model=MODEL, max_tokens=4000, system=SYSTEM,
                                  messages=[{"role": "user", "content": content}])
    text = "".join(b.text for b in resp.content if getattr(b, "type", "") == "text")
    try:
        return parse_json(text)
    except Exception:
        return {"hata": "Model cevabı okunamadı", "ham_cevap": text}


@app.get("/health")
def health():
    return {"ok": True, "demo": client is None, "model": MODEL}


@app.post("/analyze")
def analyze(
    photos: list[UploadFile] = File(...),
    district: str = Form(...),
    crop: str = Form(...),
    variant: str = Form(""),
    note: str = Form(""),
    x_app_token: str = Header(default=""),
):
    check_token(x_app_token)
    if not photos or len(photos) > MAX_PHOTOS:
        raise HTTPException(400, f"1-{MAX_PHOTOS} fotoğraf gönderin")
    rec_id = datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6]
    saved, b64s = [], []
    for i, f in enumerate(photos):
        raw = f.file.read()
        try:
            b64s.append(prepare_for_api(raw))
        except Exception:
            raise HTTPException(400, "Fotoğraf okunamadı")
        ext = Path(f.filename or "").suffix.lower() or ".jpg"
        name = f"{rec_id}_{i + 1}{ext}"
        (PHOTOS / name).write_bytes(raw)  # orijinal, eğitim verisi için
        saved.append(name)
    label = crop + (f" ({variant})" if variant else "")
    demo = client is None
    try:
        result = demo_result(label) if demo else analyze_with_model(b64s, district, label, note)
    except Exception as e:
        raise HTTPException(502, f"Analiz servisi hatası: {type(e).__name__}")
    with db() as con:
        con.execute(
            "INSERT INTO records (id, created_at, district, crop, variant, note, photos, ai_json, demo) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (rec_id, datetime.now().isoformat(timespec="seconds"), district, crop, variant,
             note, json.dumps(saved), json.dumps(result, ensure_ascii=False), int(demo)))
    return {"id": rec_id, "demo": demo, "result": result}


@app.post("/feedback/{rec_id}")
def feedback(rec_id: str, body: dict, x_app_token: str = Header(default="")):
    check_token(x_app_token)
    verdict = body.get("verdict")
    if verdict not in ("dogru", "yanlis", "belirsiz"):
        raise HTTPException(400, "verdict: dogru | yanlis | belirsiz")
    with db() as con:
        cur = con.execute(
            "UPDATE records SET verdict=?, correct_diagnosis=?, fb_note=?, fb_at=? WHERE id=?",
            (verdict, (body.get("correct_diagnosis") or "").strip(), (body.get("note") or "").strip(),
             datetime.now().isoformat(timespec="seconds"), rec_id))
        if cur.rowcount == 0:
            raise HTTPException(404, "Kayıt bulunamadı")
    return {"ok": True}


@app.get("/records")
def records(limit: int = 100, x_app_token: str = Header(default="")):
    check_token(x_app_token)
    with db() as con:
        rows = con.execute("SELECT * FROM records ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        d["photos"] = json.loads(d["photos"])
        d["ai_json"] = json.loads(d["ai_json"])
        out.append(d)
    return out


@app.get("/export.csv", response_class=PlainTextResponse)
def export_csv(x_app_token: str = Header(default="")):
    check_token(x_app_token)
    with db() as con:
        rows = con.execute("SELECT * FROM records ORDER BY created_at").fetchall()
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["id", "tarih", "ilce", "urun", "tur", "not", "fotograflar",
                "ai_ilk_teshis", "ai_guven", "dogrulama", "dogru_teshis", "uzman_notu", "demo"])
    for r in rows:
        ai = json.loads(r["ai_json"])
        t = (ai.get("teshisler") or [{}])[0]
        w.writerow([r["id"], r["created_at"], r["district"], r["crop"], r["variant"], r["note"],
                    ";".join(json.loads(r["photos"])), t.get("ad", ""), t.get("guven", ""),
                    r["verdict"] or "", r["correct_diagnosis"] or "", r["fb_note"] or "", r["demo"]])
    return buf.getvalue()
