# Bitki Asistanı

![Durum: Alfa](https://img.shields.io/badge/durum-alfa-orange)

Ziraat mühendislerinin arazi gezilerinde bitki sağlığını kontrol etmesine yardımcı olan, fotoğraf tabanlı bir Android uygulaması. Bir ziraat mühendisinin ihtiyacından yola çıkılarak geliştirilmiştir. Bitkinin fotoğrafı çekilir, yapay zekâ olası hastalık, zararlı ya da besin eksikliklerini güven düzeyiyle birlikte listeler, uzman sonucu doğrular ya da düzeltir ve bu kayıt gelecekte bölgeye özel bir model eğitmek için veri olarak birikir.

> **Alfa sürüm.** Bu proje bir prototiptir. Yalnızca geliştirme ortamında (USB ile bağlı tek bir test telefonu ve yerel sunucu) denenmiştir. Teşhis doğruluğu henüz sistematik olarak ölçülmemiştir. Üretimde ya da gerçek tarım kararlarında tek başına kullanılmamalıdır.

## Durum

| Özellik | Durum |
|---|---|
| İlçe ve ürün seçimi (Mersin, 11 ilçe, 44 ürün) | ✅ Çalışıyor |
| Kameradan / galeriden 1-4 fotoğraf ekleme | ✅ Çalışıyor |
| Yapay zekâ ile fotoğraf analizi (olası teşhisler, güven yüzdesi, öneri) | ✅ Çalışıyor |
| Ürün–fotoğraf uyuşmazlığı ve yetersiz fotoğraf uyarıları | ✅ Çalışıyor |
| Uzman değerlendirmesi (Doğru / Yanlış / Emin değilim + doğru teşhis) | ✅ Çalışıyor |
| Kayıtların CSV olarak dışa aktarılması ve özet raporu | ✅ Çalışıyor |
| Bulutta barındırılan sunucu | ⏳ Planlı |
| Kayıtların bulutta saklanması (Supabase) | ⏳ Planlı |
| Dağıtıma uygun APK | ⏳ Planlı |
| İnternetsiz kullanım ve sonradan senkronizasyon | ⏳ Planlı |
| Uygulama içi kayıt geçmişi | ⏳ Planlı |
| Cihaz üzerinde çalışan, bölgeye özel görüntü modeli | 🔭 Uzun vadeli (yeterli doğrulanmış veri birikince) |

## Nasıl çalışır

```
Android uygulaması (Flutter)
        │  fotoğraf + ilçe + ürün + not
        ▼
Python sunucusu (FastAPI)  ──►  Claude API (görsel analiz)
        │
        ▼
SQLite kayıtları + orijinal fotoğraflar
        ▲
        │  uzman değerlendirmesi (doğru / yanlış / emin değilim)
Android uygulaması
```

API anahtarı yalnızca sunucuda durur, uygulamanın içinde bulunmaz.

## Teknolojiler

- **Mobil uygulama:** Flutter (Dart)
- **Sunucu:** Python, FastAPI, SQLite, Pillow
- **Görsel analiz:** Anthropic Claude API
- **Veri:** Mersin ilçelerine göre ürün listesi (`app/assets/crops.json`)

## Kurulum

Gereksinimler: Python 3.10+, Flutter SDK, Android Studio (Android SDK), Android telefon (USB hata ayıklama açık) ve bir Anthropic API anahtarı.

### Sunucu

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env     # ANTHROPIC_API_KEY değerini yazın; boş bırakılırsa DEMO modu (sahte sonuç)
uvicorn main:app --host 0.0.0.0 --port 8000
```

### Uygulama

```bash
cd app
flutter pub get
adb reverse tcp:8000 tcp:8000   # telefon, bilgisayardaki sunucuya localhost:8000 ile ulaşır
flutter run
```

Uygulamada sağ üstteki dişliden **Bağlantıyı dene** ile sunucu bağlantısı ve DEMO / gerçek mod doğrulanabilir.

### Kayıtlara bakmak

```bash
cd server
python3 ozet.py        # kayıt sayıları, modelin doğruluğu, yanlış bulunan vakalar
```

Tüm kayıtlar: `http://localhost:8000/export.csv`

## Veri ve gizlilik

- Fotoğraflar ve kayıtlar `server/data/` altında yerel olarak saklanır ve depoya dahil edilmez.
- Fotoğraflar konum ve üçüncü kişilere ait tarım arazilerini içerebilir. Gerçek kullanımda ilgili kişilerin bilgisi ve izni gerekir.
- `.env` dosyası (API anahtarı) depoya eklenmemelidir.

## Sınırlamalar

- Sonuçlar yapay zekâ tahminidir; kesin teşhis yerine geçmez, son karar uzmana aittir.
- Kimyasal ilaç dozu ya da ticari ürün önerilmez, öneriler genel düzeydedir.
- Model yalnızca fotoğraftaki görünür belirtilere dayanır; benzer belirtiler veren sorunları (mantar, besin eksikliği, çevresel stres) birbirinden ayırmakta hata yapabilir.
- Henüz internet olmadan çalışmaz.

## Yol haritası

1. Gerçek vakalarla doğruluğun ölçülmesi ve istem (prompt) iyileştirmesi
2. Sunucunun buluta, kayıtların Supabase'e taşınması
3. Dağıtıma uygun APK ve gerçek kullanıcı testi
4. Çevrimdışı çekim ve sonradan gönderme
5. Birikmiş uzman onaylı veriyle, en sık görülen sorunlar için cihaz üzerinde çalışan küçük bir görüntü modeli

## Geliştirme notu

Proje, Claude (Anthropic) ile yapay zekâ destekli bir süreçte geliştirilmiştir.
