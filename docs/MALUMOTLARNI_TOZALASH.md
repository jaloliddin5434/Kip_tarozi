# Test-ma'lumotlarni tozalash

Skript: [scripts/malumotlarni_tozalash.ps1](../scripts/malumotlarni_tozalash.ps1)

## Qachon ishlatiladi

Haqiqiy mavsum (ishlab chiqarish) boshlanishidan oldin, sinov davrida
yig'ilgan barcha tortish ma'lumotlarini o'chirib, bazani "nolga qaytarish"
kerak bo'lganda. Masalan: test bosqichida operator ekranida sinov uchun
tortilgan kiplar, ochilgan/yopilgan test partiyalari, sinov audit yozuvlari
— bularning barchasi haqiqiy sotuv/hisobot ma'lumotlariga aralashib
qolmasligi uchun tozalanadi.

**Kunlik ishlatish uchun emas** — faqat bir martalik "nolga qaytarish"
vazifasi (masalan yangi mavsum boshida).

## Nima qiladi

- **O'chiradi** (barcha qatorlar, id ketma-ketliklari 1'dan qayta
  boshlanadi): `kiplar`, `partiyalar`, `audit_log`, `shubhali_holatlar`.
- **Tegmaydi**: `foydalanuvchilar` (login/parollar), `mahsulotlar`,
  `stansiyalar`, `sozlamalar` — bular saqlanib qoladi, qayta sozlash shart
  emas.
- Tozalashdan oldin [scripts/backup_yarat.ps1](../scripts/backup_yarat.ps1)
  orqali **avtomatik to'liq backup** oladi. Backup muvaffaqiyatsiz tugasa
  (masalan Postgres ishlamayotgan bo'lsa), tozalash BOSHLANMAYDI.
- Ishga tushirishda ogohlantirish ko'rsatadi va qo'lda aniq **"HA"** deb
  yozishni talab qiladi — boshqa har qanday javob (bo'sh qator ham) bekor
  qiladi, hech narsa o'chirilmaydi.

## Ishga tushirish

```
powershell -ExecutionPolicy Bypass -File scripts\malumotlarni_tozalash.ps1
```

Skript `backend\.env` dagi `DATABASE_URL`'ni o'qiydi — qaysi bazaga
ulanayotganini ("Baza: ...") backup bosqichida ko'rsatadi, shuni tekshirib
keyin "HA" deb yozing.

Muvaffaqiyatli tugasa oxirida shu chiqadi:

```
Tozalandi: kiplar, partiyalar, audit_log, shubhali_holatlar
Tegilmadi: foydalanuvchilar, mahsulotlar, stansiyalar, sozlamalar
```

## Agar noto'g'ri ishga tushirilsa

Tozalashdan oldin avtomatik olingan backup
`C:\Kip_tarozi\backups\kip_tarozi_YYYY-MM-DD_HHmm.dump` faylida turadi.
Tiklash — [BACKUP.md](BACKUP.md#tiklashni-sinash-restore-test) bo'limidagi
`pg_restore` bosqichlariga qarang.

## Sinovdan qanday o'tkazilgan (ishlab chiquvchi eslatmasi)

Bu skript hech qachon haqiqiy/rivojlantirish bazasiga qarshi sinalmagan.
Sinov alohida, vaqtincha yaratilgan `kip_tarozi_clear_test` bazasida
(bir xil Postgres serverda, bir xil sxema, qo'lda kiritilgan sinov
qatorlari — barcha 8 jadvalda) o'tkazilgan:

- Barcha 4 nishon jadval (`kiplar`, `partiyalar`, `audit_log`,
  `shubhali_holatlar`) muvaffaqiyatli 0'ga tushdi, id ketma-ketligi 1'dan
  qayta boshlandi.
- Qolgan 4 jadval (`foydalanuvchilar`, `mahsulotlar`, `stansiyalar`,
  `sozlamalar`) — qatorlar soni va tarkibi (masalan login/rol) o'zgarishsiz
  qoldi.
- Tozalashdan oldin avtomatik backup chaqirilgani va muvaffaqiyatli
  tugagani tasdiqlandi.
- "HA" o'rniga boshqa matn kiritilganda skript exit code 1 bilan bekor
  qilgani va hech qanday qatorga tegmagani tasdiqlandi.

Sinov bazasi so'ngida o'chirilgan (`DROP DATABASE
kip_tarozi_clear_test`).
