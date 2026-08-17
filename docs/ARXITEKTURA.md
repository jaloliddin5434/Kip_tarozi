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
talabiga mos keladi. **Muhim tarix**: dastlab (4-bosqich oxirigacha) `Kip`/
`ShubhaliHolat`da `stansiya_id` maydoni sxemada bor edi, lekin uni hech kim
to'ldirmasdi — ya'ni ko'p-stansiyalilik faqat "qog'ozda" tayyor edi. Keyinchalik
buni to'g'irladik: Stansiya Agentining `.env`ida `STANSIYA_ID` (agentning o'z
identifikatori), Flutterda `ApiClient.stansiyaId` (build/konfiguratsiya bo'yicha)
qo'shildi va ikkalasi ham mos so'rovlarga (`POST /kiplar`,
`POST /shubhali-holatlar`) `stansiya_id` sifatida uzatiladi — endi haqiqatan
ham DB'da saqlanadi (real Postgresda tekshirilgan). Yangi stansiya qo'shish:
(1) `stansiyalar` jadvaliga yangi qator, (2) yangi agentning `.env`ida boshqa
`STANSIYA_ID`, (3) yangi Flutter build/konfiguratsiyada boshqa `stansiyaId` —
backend kodi o'zgarmaydi. Hujjatlar/Statistika bo'limlarida stansiya bo'yicha
filtrlash hali qo'shilmagan (kerak bo'lsa qo'shiladi).

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

## Moliyaviy bo'lim nega alohida token bilan himoyalangan?

Oddiy Admin login (uzoq muddatli JWT) yetarli emas — moliyaviy ma'lumotlarga
kirish uchun qo'shimcha parol (`POST /moliyaviy/parolni-ornatish` orqali
o'rnatiladi, hash `sozlamalar` jadvalida saqlanadi) va alohida, QISQA
muddatli (`MOLIYAVIY_TOKEN_MUDDATI_DAQIQA`, default 30 daqiqa) token talab
qilinadi. Bu token oddiy JWT'ning ustiga emas, uning O'RNIGA ishlatiladi —
`joriy_moliyaviy_foydalanuvchi` dependency faqat `moliyaviy: true` claim'i
bor tokenlarni qabul qiladi. Amalda: Flutter/admin panel avval oddiy token
bilan ishlaydi, moliyaviy bo'limga kirganda alohida so'rov bilan bu tokenni
oladi va faqat shu bo'lim so'rovlarida ishlatadi.

## Flutter nega hozircha Stansiya Agentiga emas, backendga to'g'ridan-to'g'ri ulanadi?

2-bosqichda RS232 agent orqali offline-navbat arxitekturasi (Flutter →
Agent → Backend) loyihalashtirilgan edi. 4-bosqichda, RS232'ning haqiqiy
qurilmasi hali yo'qligi sababli, operator ekrani og'irlikni QO'LDA
kiritish bilan simulyatsiya qiladi — bu holatda kip-saqlashni agent orqali
o'tkazish sun'iy bo'lardi (agent na real vazn oqimini, na anti-o'g'irlik
holatini kuzatib turadi). Shu sababli Flutter hozircha auth, partiya, kip,
statistika va h.k. uchun backendga TO'G'RIDAN-TO'G'RI (REST) ulanadi;
"Yuk saqlanmadi" bloklovchi modal esa backend darajasidagi
`GET /shubhali-holatlar/bloklovchi`ni pollash orqali ishlaydi (agentning
lokal holatidan mustaqil, DB — yagona haqiqat manbai). RS232 real qurilma
ulangach, kip-saqlash yo'lini agent orqali (`POST /agent/kip`) o'tkazish —
Flutter tomonidagi bitta funksiya almashtiruvi, backend o'zgarmaydi.

## RS232 parslash nega bitta regex bilan qilingan?

Indikator modeli hali aniqlanmagan. `RS232_REGEX` (.env) — qatordan `vazn`
named group orqali og'irlikni ajratib oladigan konfiguratsiya. Model
aniqlangach, agar format regex bilan yetarli bo'lmasa (masalan checksum yoki
binary protokol), `OgirlikOquvchi.oqish_tsikli()` shu model uchun almashtiriladi
— qolgan tizim (bus, stability, watchdog, agent API) o'zgarmaydi.
