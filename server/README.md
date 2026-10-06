# Sunucu
```
cd ~/bitki-asistani/server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # sonra .env içine ANTHROPIC_API_KEY yazın (boşsa DEMO modu)
uvicorn main:app --host 0.0.0.0 --port 8000
```
- Kayıtlar `data/kayitlar.db`, fotoğraflar `data/photos/` içinde.
- Tüm kayıtlar: http://localhost:8000/export.csv
