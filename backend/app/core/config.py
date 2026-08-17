from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Baza
    DATABASE_URL: str

    # Xavfsizlik
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 5256000  # ~10 yil — sessiya muddati cheklanmagan

    # Login blok qoidasi
    LOGIN_MAX_ATTEMPTS: int = 10
    LOGIN_LOCKOUT_MINUTES: int = 5

    # Fayllar
    STORAGE_PATH: str = "./storage"

    # RS232 (indikator modeli aniqlangach o'zgaradi — bu yerda faqat default qiymatlar)
    RS232_PORT: str = "COM3"
    RS232_BAUDRATE: int = 9600
    RS232_BYTESIZE: int = 8
    RS232_PARITY: str = "N"
    RS232_STOPBITS: int = 1
    RS232_TIMEOUT: float = 1.0
    RS232_REGEX: str = r"(?P<vazn>[+-]?\d+\.?\d*)\s*kg"
    RS232_RECONNECT_SECONDS: int = 5

    # Stability-check
    STABILITY_SECONDS: float = 3.0
    STABILITY_TOLERANCE_KG: float = 0.2

    # Anti-o'g'irlik nazorati
    ANTI_OGIRLIK_THRESHOLD_KG: float = 130.0
    ANTI_OGIRLIK_PASTGA_TUSHISH_KG: float = 10.0

    # Kip saqlashdagi biznes qoidalari
    DUPLIKAT_VAQT_OYNASI_SONIYA: float = 15.0
    DUPLIKAT_OGIRLIK_TOLERANSI_KG: float = 0.5
    BEKOR_QILISH_MUDDATI_SONIYA: int = 30

    # Stansiya Agenti <-> Backend ichki aloqasi
    # Agentning o'zi qaysi stansiya ekanini bildiradi (`stansiyalar.id`) — shubhali
    # holat hodisalarida shu qiymat backendga uzatiladi. Kelajakda 2+ stansiya
    # bo'lganda har birining .env'ida boshqa-boshqa qiymat qo'yiladi.
    STANSIYA_ID: int | None = None
    AGENT_API_KEY: str = "CHANGE_ME_AGENT_KEY"
    BACKEND_URL: str = "http://localhost:8000"
    AGENT_QUEUE_DB_PATH: str = "./storage/agent_navbat.db"
    AGENT_SYNC_INTERVAL_SONIYA: int = 15
    AGENT_HOLAT_YUBORISH_SONIYA: int = 30
    # Shu muddatdan uzoq vaqt xabar kelmasa, dashboard agentni "offline" deb ko'rsatadi
    AGENT_HOLAT_ESKIRISH_SONIYA: int = 90

    # Kamera (snapshot HTTP endpoint — indikator kabi, model aniqlangach o'zgaradi)
    CAMERA_SNAPSHOT_URL: str | None = None

    # Kunlik Telegram hisoboti (F.3)
    VAQT_ZONASI: str = "Asia/Tashkent"
    KUNLIK_HISOBOT_VAQTI: str = "20:00"

    # Moliyaviy bo'lim — qo'shimcha parol bilan himoyalangan qisqa muddatli sessiya
    MOLIYAVIY_TOKEN_MUDDATI_DAQIQA: int = 30

    # Brend
    BRAND_COLOR: str = "#0F6E56"

    ENV: str = "dev"


settings = Settings()
