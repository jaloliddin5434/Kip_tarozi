# Arxitektura qarorlari

## Nega backend va RS232 agent alohida jarayon?

Tarozi va kamera jismonan operator kompyuteriga (COM port, LAN kamera)
ulangan, VPS'ga emas. Shu sababli RS232 o'qish VPS'da FastAPI backend ichida
emas, operator kompyuterida alohida yengil FastAPI ilovasi
(`app/services/rs232/station_agent.py`) sifatida ishlaydi:

- Operator kompyuterida NSSM orqali Windows xizmati sifatida o'rnatiladi —
  kompyuter yoqilganda avtomatik ishga tushadi, interfeys yopilsa ham ishlashda
  davom etadi (mavjud tarozi-tizimidagi pattern).
- Flutter operator ekrani shu agentga `localhost` orqali ulanadi
  (`GET /holat`, `WS /oqim`) — real-vaqt og'irlik va ulanish holatini oladi.
- Asosiy backend (VPS, PostgreSQL) o'zi RS232 bilan bevosita ishlamaydi.

**2-bosqich (offline queue) bilan bu bir qadam kengaydi:** Flutter kip
saqlashni ham to'g'ridan-to'g'ri VPS backendga emas, `POST /agent/kip` orqali
shu agentga yuboradi. Agent operatorning tokenini o'zgartirmasdan backendga
forward qiladi; agar backend/internet ishlamasa, yozuvni mahalliy SQLite
navbatga (`AGENT_QUEUE_DB_PATH`) qo'yadi va fon thread orqali aloqa
tiklanganda avtomatik qayta yuboradi (`POST /api/v1/kiplar/sinxron`,
operator tomonida generatsiya qilingan `mijoz_id` UUID orqali dublikatning
oldi olinadi). Bu ajratish operatorning kip saqlashi HAR DOIM bitta joydan —
doimo ishlaydigan mahalliy xizmatdan — o'tishini ta'minlaydi, Flutter'ning
o'zida alohida offline mantiq qurish shart emas.

Anti-o'g'irlik state machine (`app/services/rs232/anti_ogirlik.py`) ham shu
agent ichida, RS232 o'qish tsiklidan alohida (`OgirlikKanali` orqali)
ishlaydi — shuning uchun operator "Saqlash" tugmasini bosmasa ham yukning
qo'yilib-olib qo'yilganini kuzatib turadi. Hodisa yuzaga kelganda agent
o'zi kameradan surat oladi (`CAMERA_SNAPSHOT_URL`) va backendga
`AGENT_API_KEY` bilan (foydalanuvchi tokeni emas — bu operator amalidan
mustaqil, avtomatik hodisa) yuboradi.

Bu ajratish 7-bandda aytilgan "kelajakda qo'shimcha tortish stansiyalari"
talabiga ham mos keladi: har bir yangi stansiya — o'zining agenti + `stansiyalar`
jadvalidagi yozuvi, backend o'zgarmaydi.

## Offline navbatda qanday chegaralar bor (2-bosqich holatida)

- `/kiplar/sinxron` dublikat-ogohlantirish va anti-o'g'irlik blokini
  TEKSHIRMAYDI — bular offline paytda operator tomonidan allaqachon qaror
  qilingan haqiqiy amallar, ularni qayta bloklash offline ma'lumotni
  yo'qotib qo'yishi mumkin.
- Agar Stansiya Agenti qayta ishga tushsa (masalan kompyuter restart bo'lsa)
  bloklangan-holatdagi xotira yo'qoladi; DB'dagi tasdiqlanmagan
  `shubhali_holatlar` hali ham `POST /api/v1/kiplar` darajasida bloklab
  turadi (backend har doim tekshiradi), faqat agentning lokal indikatori
  operatorga darhol ko'rinmasligi mumkin. 3-bosqichda kerak bo'lsa
  agent-startup sinxronizatsiyasi qo'shiladi.
- Kip suratlari (audit uchun) hozircha faqat yo'l sifatida uzatiladi —
  haqiqiy fayl yuklash endpoint'i Flutter kamera UI qurilganda qo'shiladi.
  Shubhali holat suratlari esa (kritik bo'lgani uchun) to'liq ishlaydi.

## Nega SQLAlchemy sync (async emas)?

Bitta stansiya, o'rtacha yuklama uchun sync SQLAlchemy + FastAPI'ning threadpool
executor'i yetarli va soddaroq. Agar kelajakda ko'p stansiya/WebSocket yuklamasi
ortsa, alohida qaror sifatida asyncpg'ga o'tish mumkin.

## RS232 parslash nega bitta regex bilan qilingan?

Indikator modeli hali aniqlanmagan. `RS232_REGEX` (.env) — qatordan `vazn`
named group orqali og'irlikni ajratib oladigan konfiguratsiya. Model
aniqlangach, agar format regex bilan yetarli bo'lmasa (masalan checksum yoki
binary protokol), `OgirlikOquvchi.oqish_tsikli()` shu model uchun almashtiriladi
— qolgan tizim (bus, stability, watchdog, agent API) o'zgarmaydi.
