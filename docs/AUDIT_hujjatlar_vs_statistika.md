# AUDIT — Hujjatlar vs Statistika ekranlari ma'lumot mosligi

**Sana:** 2026-09-09
**Turi:** Faqat audit — hech qanday kod o'zgartirilmadi.
**Baza:** dev (`localhost:47432/kip_tarozi`), faqat O'QISH so'rovlari bilan tekshirildi.

---

## 1. Qisqacha xulosa

| | Hujjatlar (`/hujjatlar/kiplar`) | Statistika (`/statistika/*`, `/hisobotlar/*`, `/dashboard`) |
|---|---|---|
| **"Aktiv kip" ta'rifi** | **YO'Q** — sukut bo'yicha barcha holatdagi kiplar (aktiv + bekor_qilingan + tahrirlangan) | **Doimo `holati = 'aktiv'`** |
| Sana oralig'i | `func.date(Kip.vaqt) >= dan AND <= gacha` (inklyuziv) | `func.date(Kip.vaqt) >= boshlanish AND <= tugash` (inklyuziv) |
| Smena filtri | `Kip.smena == smena` | `Kip.smena == smena` |
| Mahsulot filtri | `Mahsulot.kod == kod` | `Mahsulot.kod == kod` |
| Vaqt zonasi | DB sessiya TZ'da `func.date()` | DB sessiya TZ'da `func.date()` |

**Asosiy topilma:** Sana / smena / mahsulot / vaqt-zona mantig'i **to'liq bir xil**. Yagona, ammo tizimli nomuvofiqlik — **"aktiv kip" ta'rifi**: Statistika bekor qilingan va tahrirlangan kiplarni chiqarib tashlaydi, Hujjatlar esa ularni jadvalga qo'shadi. Natijada bekor/tahrirlangan kip bo'lgan har qanday kun/oy/mavsumда Hujjatlar jadvalidagi "jami" va qo'lda hisoblangan kg Statistikadan katta bo'ladi.

---

## 2. Sinovdan o'tkazilgan stsenariylar (dev baza)

Har bir stsenariy uchun ikkala ekranning **aniq SQL mantig'i** takrorlandi:
`kiplar JOIN partiyalar JOIN mahsulotlar (JOIN foydalanuvchilar — Hujjatlar)`, so'ng Statistika uchun `+ holati='aktiv'`.

| Stsenariy | Hujjatlar (qator / kg) | Statistika (soni / kg) | Natija |
|---|---|---|---|
| Bugun (09-09) / Barchasi / Barchasi | 5 / 1106.60 | 5 / 1106.60 | ✅ ANIQ MOS |
| Bugun / smena A / tola | 0 / 0 | 0 / 0 | ✅ MOS |
| Bugun / smena B / lint | 0 / 0 | 0 / 0 | ✅ MOS |
| Shu hafta (07–13 sen) / Barchasi | 11 / 2366.40 | 11 / 2366.40 | ✅ MOS |
| Sentabr oyi / Barchasi | 24 / 4997.70 | 24 / 4997.70 | ✅ MOS |
| Mavsum (01 sen – bugun) | 24 / 4997.70 | 24 / 4997.70 | ✅ MOS |
| **Avgust oyi / Barchasi** | **43 / 9468.00** | **42 / 9248.00** | ❌ **FARQ: 1 qator, 220 kg** |
| **Butun tarix (2026)** | **67 / 14465.70** | **66 / 14245.70** | ❌ **FARQ: 1 qator, 220 kg** |
| **16-avgust / Barchasi** | **1 / 220.00** | **0 / 0** | ❌ **FARQ: 1 qator, 220 kg** |

**Farqning aniq sababi:** dev bazada aynan bitta bekor qilingan kip bor —
`kip id=1, sana=2026-08-16, smena=A, mahsulot=tola, og'irlik=220.00 kg, holati='bekor_qilingan'`.
Bu kip Hujjatlar jadvalida ko'rinadi (qizil fon bilan), Statistikaning har bir raqamidan esa chiqarib tashlangan. Boshqa hech qanday nomuvofiqlik topilmadi — qolgan 5 stsenariyda sonlar bayt-bayt mos keldi.

> Bazada hozircha **`tahrirlangan` holatidagi kip yo'q**, shuning uchun tahrirlash bo'yicha farq amalda hali yuzaga chiqmagan (pastdagi FINDING 2 ga qarang — bu latent muammo).

---

## 3. Topilgan nomuvofiqliklar

### FINDING 1 — Hujjatlar "aktiv" filtrini qo'llamaydi, Statistika esa doimo qo'llaydi  *(tasdiqlangan)*

**Backend**
- [backend/app/api/v1/routes/hujjatlar.py:29](../backend/app/api/v1/routes/hujjatlar.py#L29) — `holati` parametri **ixtiyoriy**, sukut bo'yicha `None`.
- [backend/app/api/v1/routes/hujjatlar.py:54-55](../backend/app/api/v1/routes/hujjatlar.py#L54-L55) — `holati` faqat foydalanuvchi uni yuborgandagina `WHERE`ga qo'shiladi.
- Statistika — barcha so'rovlar qattiq `Kip.holati == KipHolati.aktiv`:
  - [statistika.py:59](../backend/app/api/v1/routes/statistika.py#L59) `jamlanma`
  - [statistika.py:96](../backend/app/api/v1/routes/statistika.py#L96) `smena-boyicha`
  - [statistika.py:128](../backend/app/api/v1/routes/statistika.py#L128) `operator-boyicha`
  - [statistika.py:163](../backend/app/api/v1/routes/statistika.py#L163) va [statistika.py:200](../backend/app/api/v1/routes/statistika.py#L200) `rekordlar`
  - [dashboard.py:71](../backend/app/api/v1/routes/dashboard.py#L71), [dashboard.py:85](../backend/app/api/v1/routes/dashboard.py#L85)
  - [hisobotlar.py:58](../backend/app/api/v1/routes/hisobotlar.py#L58), [hisobotlar.py:127](../backend/app/api/v1/routes/hisobotlar.py#L127), [hisobotlar.py:215](../backend/app/api/v1/routes/hisobotlar.py#L215)
  - [rejalashtiruvchi.py:28](../backend/app/services/rejalashtiruvchi.py#L28) (kunlik Telegram hisoboti)

**Frontend**
- [frontend/lib/screens/admin/hujjatlar_screen.dart:33-34](../frontend/lib/screens/admin/hujjatlar_screen.dart#L33-L34) — `_holatiFiltri` sukut bo'yicha `null`.
- [hujjatlar_screen.dart:94](../frontend/lib/screens/admin/hujjatlar_screen.dart#L94) — `_holatiFiltri != null` bo'lgandagina query'ga qo'shiladi; ekran ochilishida (`initState`, 41–46-qatorlar) faqat "bugun" sana filtri qo'yiladi, holati emas.
- [hujjatlar_screen.dart:528](../frontend/lib/screens/admin/hujjatlar_screen.dart#L528) — sahifalash qatoridagi `(jami: N)` — bu `sahifa.jami`, ya'ni **barcha holatdagi** kiplar soni.
- Statistika: [statistika_screen.dart:350-352](../frontend/lib/screens/admin/statistika_screen.dart#L350-L352) — "Jami" / "Jami (kg)" kartalari `holati='aktiv'` bo'yicha kelgan raqamlarni ko'rsatadi.

**Amaliy oqibat**
- Admin ikkala ekranни solishtirsa, bekor qilingan yoki tahrirlangan kip bo'lgan istalgan davrda Hujjatlardagi qator soni / kg Statistikadan katta chiqadi va qaysi biri "to'g'ri" ekani noaniq bo'ladi.
- Hujjatlar ekranidan chop etilgan PDF (`kipHujjatiQur`) va qo'lda hisob-kitob rasmiy Statistika/hisobot raqamlariga to'g'ri kelmaydi.
- Xaridor yoki auditor oldida "sotilgan/tortilgan kiplar soni" bo'yicha ikki xil raqam paydo bo'ladi.

---

### FINDING 2 — `tahrirlangan` kiplar BARCHA statistikadan butunlay tushib qoladi  *(latent, hozircha yuzaga chiqmagan, ammo jiddiy)*

**Sabab**
- [backend/app/api/v1/routes/kiplar.py:485](../backend/app/api/v1/routes/kiplar.py#L485) — admin kipни tahrirlaganda (`PATCH /kiplar/{id}`) `kip.holati = KipHolati.tahrirlangan` **shartsiz** o'rnatiladi (og'irlik tuzatilsa ham, mahsulot/partiya to'g'rilansa ham).
- Butun kod bazasida `holati`ni qayta `aktiv`ga qaytaradigan **birorta ham** endpoint yo'q (grep bilan tekshirildi) — ya'ni tahrir = doimiy.
- Statistika/hisobotlarning hammasi `holati == KipHolati.aktiv` **aniq tengligini** talab qiladi (`!= bekor_qilingan` emas).

**Natijada tahrirlangan kip quyidagilarning HAMMASIDAN chiqadi:**
`/statistika/jamlanma` (kunlik/haftalik/oylik/mavsum + kalendar kun tafsiloti), `/statistika/smena-boyicha`, `/statistika/operator-boyicha`, `/statistika/rekordlar` (shu jumladan "barcha vaqt kunlik rekord"), `/hisobotlar/smena-excel`, `/hisobotlar/smena-mahsulot-excel`, `/hisobotlar/mavsum-jurnali`, `/dashboard`, kunlik Telegram hisoboti, **va** sotilgan partiyaning aktiv-kip sanog'i — [partiyalar.py:154](../backend/app/api/v1/routes/partiyalar.py#L154), u [partiyalar.py:158](../backend/app/api/v1/routes/partiyalar.py#L158) `nakladnoy_pdf_yarat(...)` ga `kip_soni` sifatida uzatiladi.

Lekin Hujjatlar jadvalida ko'rinishda qoladi ([hujjatlar_screen.dart:443-447](../frontend/lib/screens/admin/hujjatlar_screen.dart#L443-L447) — to'q sariq fon).

**Amaliy oqibat**
- Admin xato kiritilgan og'irlikni tuzatsa (masalan 1500 → 150 kg) yoki kipни noto'g'ri partiyadan to'g'risiga ko'chirsa — jismonan mavjud kip ishlab chiqarish jamlanmasidan, smena va operator reytingidan, rekordlardan, mavsum jurnalidan **butunlay yo'qoladi**. Tuzatilgan qiymat ham hisobga olinmaydi — ya'ni tahrir "tuzatish" emas, amalda "o'chirish" bilan bir xil ishlaydi (holbuki `bekor_qilingan` degan alohida holat aynan shu maqsad uchun bor).
- **Nakladnoy (yuk xati)** — rasmiy sotuv hujjati — sotilgan partiyada jismoniy kiplar sonini kam ko'rsatadi.
- Ishlab chiqarish har bir tahrirlangan kip miqdoricha tizimli ravishda kam hisoblanadi.

**Isbot**
- Mexanizm FINDING 1 dagi bekor qilingan kip stsenariysi bilan aynan bir xil (16-avgust: Hujjatlar 1/220, Statistika 0/0). Dev bazada tahrirlangan kip bo'lmagani uchun aynan shu holat hozircha ko'rinmaydi — birinchi tahrirdayoq boshlanadi.
- Testlar bu holatni qamramaydi: [backend/tests/test_statistika.py:172](../backend/tests/test_statistika.py#L172) faqat `bekor_qilingan` kipни sinaydi, `tahrirlangan` hech qayerda sinalmaydi.

---

### FINDING 3 — Hujjatlar ekranining ichki nomuvofiqligi  *(tasdiqlangan)*

- [hujjatlar_screen.dart:393-397](../frontend/lib/screens/admin/hujjatlar_screen.dart#L393-L397) — "Excel yuklab olish" tugmasi `/hisobotlar/smena-excel` ni chaqiradi, u [hisobotlar.py:58](../backend/app/api/v1/routes/hisobotlar.py#L58) da `holati='aktiv'` bilan filtrlanadi.
- Xuddi shu ekrandagi jadval esa barcha holatdagi kiplarни ko'rsatadi.
- **Oqibat:** admin ekrandagi jadvalда 43 qator ko'radi, "Excel yuklab olish" bosганда esa 42 qatorli fayl oladi — bitta ekran, ikki xil son.

---

## 4. Mos kelgan (muammosiz) jihatlar — tasdiq

| Jihat | Holat |
|---|---|
| **Sana chegaralari** | ✅ Ikkalasi ham `func.date(Kip.vaqt)` orqali **sanaга trunkatsiya** qiladi va inklyuziv `>= dan AND <= gacha` solishtiradi. 00:00 / 23:59 farqi **YO'Q**, soat-daqiqa umuman ishtirok etmaydi. |
| **Vaqt zonasi** | ✅ Ikkala tomon ham `func.date()` ni bir xil DB sessiya TZ'sida (`Asia/Yekaterinburg`, UTC+5) hisoblaydi — ekranlararo siljish yo'q. Mutlaq to'g'rilik: `date.today()` server vaqtida, ammo Toshkent ham UTC+5 — offset bir xil, muammo yo'q. |
| **Smena filtri** | ✅ Ikkalasida `Kip.smena == smena` (enum). |
| **Mahsulot filtri** | ✅ Ikkalasida `Mahsulot.kod == kod` (Statistikada guruhlash orqali, Hujjatlarda bevosita `WHERE` — natija bir xil). |
| **Davr oralig'i (haftalik/oylik/mavsum)** | ✅ [davr.py](../backend/app/services/davr.py) `davr_oraligi()` inklyuziv `[boshlanish, tugash]` beradi; Hujjatlarda foydalanuvchi mos oraliqni qo'lda qo'yadi. |
| **Kalendar — kun tafsiloti** | ✅ [statistika_screen.dart:119](../frontend/lib/screens/admin/statistika_screen.dart#L119) — asosiy jamlanma bilan **aynan bir xil** `/statistika/jamlanma?davr=kunlik` endpoint. |
| **Rekord — "barcha vaqt kunlik rekord"** | ✅ [statistika.py:197-204](../backend/app/api/v1/routes/statistika.py#L197-L204) — davrga bog'liq emas, lekin `holati='aktiv'` ta'rifi qolgan statistika bilan izchil. |
| **Mavsum jurnali** | ✅ [hisobotlar.py:215](../backend/app/api/v1/routes/hisobotlar.py#L215) — `holati='aktiv'` + `func.date(Kip.vaqt)` oraliq, statistika bilan bir xil. |
| **Operator ekrani jamlanmalari** | ✅ [kiplar.py:73](../backend/app/api/v1/routes/kiplar.py#L73) (`_smena_kunlik_jamlanma`) — `holati='aktiv'`, statistika bilan izchil. `/kiplar/smena/royxat` ([kiplar.py:118](../backend/app/api/v1/routes/kiplar.py#L118)) holati filtrsiz, ammo u Hujjatlar kabi to'liq ro'yxat (badge bilan) — maqsadga mos. |
| **Kalendar vidjeti** | ✅ [kalendar_vidjeti.dart](../frontend/lib/widgets/kalendar_vidjeti.dart) — sof ko'rinish, o'z so'rovi yo'q. |

---

## 5. Yakuniy verdikt

- **9 ta stsenariy** sinovdan o'tkazildi; **6 tasida** sonlar bayt-bayt aniq mos keldi.
- **3 ta stsenariyda** (16-avgust, avgust oyi, butun tarix) farq bor — sababi **faqat va faqat bitta bekor qilingan kip** (id=1, 220 kg), Hujjatlar uni ko'rsatadi, Statistika chiqarib tashlaydi.
- **Sana / smena / mahsulot / vaqt-zona mantig'i ikkala ekranda bir xil** — bu yerda hech qanday nomuvofiqlik yo'q.
- Yagona tizimli sabab: **"aktiv kip" ta'rifi Statistikada mavjud, Hujjatlarda yo'q** (FINDING 1). FINDING 2 — shu ta'rifning `tahrirlangan` kiplarga nisbatan qo'shimcha, hali sezilmagan lekin jiddiyroq oqibati.

---

## 6. Tavsiyalar (audit doirasida — kod o'zgartirilmadi)

1. **FINDING 1** — ikki yo'ldan biri:
   - (a) Hujjatlar sukut bo'yicha `holati=aktiv` filtrини qo'llasin (chiplar orqali bekor/tahrirlanганни alohida ko'rsatish mumkin) — Statistika bilan to'liq mos bo'ladi; **yoki**
   - (b) Hujjatlar to'liq jurnal bo'lib qolsin, lekin sahifalash qatorida `aktiv: N · bekor: N · tahrirlangan: N` ko'rinishida ajratib ko'rsatilsin, toki raqamlar Statistika bilan solishtirilganda o'zi izohlansin.
2. **FINDING 2** — biznes qarori kerak: tahrirlangan kip ishlab chiqarish jamlanmasida hisoblanishi kerakmi? Agar ha (ehtimol shunday) — statistikadagi `holati == aktiv` shartlarini `holati != bekor_qilingan` ga o'zgartirish yoki tahrirlangan kipни qayta tasdiqlab `aktiv`ga qaytarish oqimini qo'shish. Har qanday holatda `test_statistika.py` ga `tahrirlangan` bo'yicha test qo'shilishi kerak.
3. **FINDING 3** — Hujjatlar ekranidagi Excel eksпорти ekrandagi jadval bilan bir xil holati filtridan foydalansин.
