"""Flutter projesini (app/) bitki asistanı için hazırlar. Güvenle tekrar çalıştırılabilir.
Kullanım:  python3 setup_app.py   (bitki-asistani klasöründe)"""
import re, subprocess, sys
from pathlib import Path

root = Path(__file__).parent
app = root / "app"
if not (app / "pubspec.yaml").exists():
    sys.exit("app/ klasöründe Flutter projesi yok. Önce: flutter create ... app")

# 1) paketler
subprocess.run(["flutter", "pub", "add", "image_picker", "http", "shared_preferences"],
               cwd=app, check=True)

# 2) assets
ps = app / "pubspec.yaml"
t = ps.read_text(encoding="utf-8")
if "assets/crops.json" not in t:
    if re.search(r"^flutter:[ \t]*$", t, re.M):
        t = re.sub(r"^flutter:[ \t]*$", "flutter:\n  assets:\n    - assets/crops.json", t,
                   count=1, flags=re.M)
    else:
        t += "\nflutter:\n  assets:\n    - assets/crops.json\n"
    ps.write_text(t, encoding="utf-8")
    print("pubspec.yaml: assets eklendi")

# 3) Android manifest: internet izni, http (localhost) izni, uygulama adı
mf = app / "android/app/src/main/AndroidManifest.xml"
m = mf.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in m:
    m = m.replace("<application",
                  '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if "usesCleartextTraffic" not in m:
    m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
m = m.replace('android:label="bitki_asistani"', 'android:label="Bitki Asistanı"')
mf.write_text(m, encoding="utf-8")
print("AndroidManifest.xml güncellendi")

# 4) varsayılan test dosyası (eski MyApp'e bağlı, analizi bozar)
wt = app / "test/widget_test.dart"
if wt.exists():
    wt.unlink()
    print("test/widget_test.dart silindi")

print("\nHazır. Şimdi:  cd app && flutter run")
