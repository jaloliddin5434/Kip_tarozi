# AUDIT — Statistika "Mavsum" davri: kutilmagan kam son

**Sana:** 2026-09-09
**Turi:** Faqat audit — hech qanday kod o'zgartirilmadi.
**Baza:** dev (`localhost:47432/kip_tarozi`), faqat O'QISH so'rovlari.

---

## 1. Bir gapda xulosa

**Bu SQL/JOIN/agregatsiya/pagination bug'i EMAS.** Backend so'rovi o'zi ishlatgan sana oralig'i uchun mutlaqo to'g'ri son qaytaradi (har bir mahsulot uchun oddiy SQL bilan bayt-bayt tekshirildi).

Yagona sabab — **"Mavsum" davrining boshlanish sanasi**:
`/statistika/jamlanma?davr=mavsum` "mavsum boshi" ni [`app/services/davr.py`](../backend/app/services/davr.py) dagi **qattiq kodlangan qoida** orqali hisoblaydi: *"mavsum har yili 1-sentyabrdan boshlanadi"*. Bugun 2026-09-09 bo'lgani uchun mavsum oralig'i = **2026-09-01 … 2026-09-09** (atigi 9 kun).

Foydalanuvchining psql so'rovi esa `vaqt >= '2025-09-01'` ni ishlatgan — bu **o'tgan** mavsum oynasi (`mavsum_boshlanish_sanasi` sozlamasi ham shu = `2025-09-01`). Ikki oyna orasidagi farq — **2026-avgust oyida tortilgan kiplar**, ular yangi mavsum (2026-09-01) chegarasidan oldin qolgan.

---

## 2. Raqamlar — aniq tasdiq (dev baza, `holati='aktiv'`)

| Mahsulot | Statistika "Mavsum" ko'rsatadi<br>(kod qoidasi: `date(vaqt) >= 2026-09-01`) | Foydalanuvchi kutgani<br>(`date(vaqt) >= 2025-09-01`) | Farq |
|---|---|---|---|
| **tola** | **16** | 30 | **14** |
| lint | 6 | 17 | 11 |
| pux | 1 | 10 | 9 |
| ulyuk | 1 | 9 | 8 |

**Backend kodi haqiqatan 16 qaytaradimi?** — Ha. `/statistika/jamlanma` endpoint funksiyasi to'g'ridan-to'g'ri chaqirilganda:
```
boshlanish=2026-09-01  tugash=2026-09-09
  lint   soni=6   kg=1204.5
  pux    soni=1   kg=242.2
  tola   soni=16  kg=3352.7
  ulyuk  soni=1   kg=198.3
  JAMI   soni=24  kg=4997.7
```

**Xuddi shu son oddiy SQL bilan (backend so'rovining qo'lda nusxasi):**
```sql
SELECT m.kod, count(k.id), coalesce(sum(k.ogirlik),0)
FROM mahsulotlar m
JOIN partiyalar p ON p.mahsulot_id = m.id
JOIN kiplar k     ON k.partiya_id  = p.id
WHERE k.holati IN ('aktiv','tahrirlangan')
  AND date(k.vaqt) >= '2026-09-01' AND date(k.vaqt) <= '2026-09-09'
GROUP BY m.kod;
--  lint=6/1204.50   pux=1/242.20   tola=16/3352.70   ulyuk=1/198.30
```
→ **Backend hisoblagan son = oddiy SQL soni. Hech qanday qator yo'qolmayapti.**

**"Yo'qolgan" 14 ta tola kip qayerda?** — Hammasi 2026-avgustда:
| sana | soni | kg |
|---|---|---|
| 2026-08-17 | 1 | 250.0 |
| 2026-08-18 | 2 | 442.0 |
| 2026-08-20 | 11 | 2419.0 |

Bular 2026-09-01 dan oldin bo'lgani uchun kodning "mavsum" oynasiga tushmaydi.

---

## 3. Ildiz sabab — aniq fayl+qator

### [backend/app/services/davr.py:6-10](../backend/app/services/davr.py#L6-L10)
```python
def mavsum_boshlanishi(sana: date) -> date:
    """Mavsum har yili 1-sentyabrdan boshlanadi."""
    if sana.month >= 9:
        return date(sana.year, 9, 1)
    return date(sana.year - 1, 9, 1)
```

### [backend/app/services/davr.py:26-27](../backend/app/services/davr.py#L26-L27)
```python
if davr == "mavsum":
    return mavsum_boshlanishi(sana), sana
```

`davr_oraligi("mavsum", <sana>)` ning haqiqiy qiymatlari:

| Bugungi sana | "Mavsum" oralig'i | tola "aktiv" soni |
|---|---|---|
| **2026-08-31** | **2025-09-01** … 2026-08-31 | **30** |
| **2026-09-01** | **2026-09-01** … 2026-09-01 | 16 (2026-09-09 gacha jamlanma) |
| **2026-09-09** (bugun) | **2026-09-01** … 2026-09-09 | **16** |

> **Ya'ni: 8 kun oldin (31-avgust) xuddi shu ekran tola uchun 30 ko'rsatardi. 1-sentyabrда yangi mavsum boshlangani sababli son avtomatik "nol"dan boshlab hisoblanadigan bo'ldi.** Bu — foydalanuvchi "ma'lumot yo'qoldi" deb o'ylashiga sabab bo'lgan holat.

### Chaqiruvchilar — hammasi shu qoidadan foydalanadi:
- [statistika.py:47](../backend/app/api/v1/routes/statistika.py#L47) `jamlanma` → `davr_oraligi(davr, sana)`
- [statistika.py:90](../backend/app/api/v1/routes/statistika.py#L90) `smena_boyicha`
- [statistika.py:115](../backend/app/api/v1/routes/statistika.py#L115) `operator_boyicha`
- [statistika.py:160](../backend/app/api/v1/routes/statistika.py#L160) `rekordlar` (davr davomidagi eng yaxshi smena/operator)
- [dashboard.py:59](../backend/app/api/v1/routes/dashboard.py#L59) `dashboard`
- [moliyaviy.py:89](../backend/app/api/v1/routes/moliyaviy.py#L89) `hisobot` (moliyaviy)

---

## 4. NIMA XATO EMAS (aniq inkor)

| Gumon | Tekshiruv natijasi |
|---|---|
| JOIN turi (INNER vs LEFT) qatorlarni yo'qotmoqda | ❌ Yo'q. Har bir kip'ning haqiqiy `partiya_id` va `mahsulot_id` bor; INNER JOIN'da hech nima tushmaydi. Oddiy SQL bilan bir xil. |
| `LIMIT` / pagination default qiymati | ❌ Yo'q. `jamlanma` — `GROUP BY` agregat so'rov, `LIMIT` yo'q, `OFFSET` yo'q. |
| Yashirin `partiya.holati` sharti | ❌ Yo'q. So'rovда `Partiya.holati` bo'yicha hech qanday filtr yo'q — ochiq/yopiq/sotilgan partiyalar bir xil sanaladi. |
| Sana solishtirish turi/formati (`func.date` vs cast) | ❌ Yo'q. `func.date(Kip.vaqt)` PostgreSQL'da `date(k.vaqt)` bilan aynan bir xil natija beradi; qo'lda solishtirildi. |
| Vaqt zonasi (00:00/23:59 chegarasi) | ❌ Yo'q. "Yo'qolgan" 14 kip 17–20-avgustда, yarim tunga yaqin emas; sessiya TZ (Asia/Yekaterinburg) izchil. |
| `holati` filtri (yaqinda `tahrirlangan` qo'shildi) | ❌ Yo'q. 2026-09 oynasida 0 ta `tahrirlangan` kip; eski `== aktiv` bilan ham natija 16. |
| Frontend noto'g'ri parametr yuboryapti | ❌ Yo'q — 5-bo'limga qarang. |

---

## 5. Frontend "Mavsum" ni to'g'ri yuboradimi? — HA

[frontend/lib/screens/admin/statistika_screen.dart:203-211](../frontend/lib/screens/admin/statistika_screen.dart#L203-L211):
```dart
_filtrQatori<String>(
  qiymatlar: const ['kunlik', 'haftalik', 'oylik', 'mavsum'],
  tanlangan: _davr,
  matn: (v) => lok.t('davr_$v'),          // faqat ko'rsatish uchun tarjima
  onTanlash: (v) { setState(() => _davr = v); _yuklash(); },   // xom kalit
);
```
[statistika_screen.dart:84](../frontend/lib/screens/admin/statistika_screen.dart#L84):
```dart
final jamlanmaQuery = <String, dynamic>{'davr': _davr};   // => davr=mavsum
```
`sana` **yuborilmaydi** → backend `sana = date.today()` (server bugungi sanasi) ni ishlatadi. To'g'ri.

Backend javob qaytarganda `boshlanish_sanasi=2026-09-01`, `tugash_sanasi=2026-09-09` — bu ekranда [statistika_screen.dart:325-328](../frontend/lib/screens/admin/statistika_screen.dart#L325-L328) da `"2026-09-01 — 2026-09-09"` matni ko'rinadi. Ma'lumot bor, lekin kichik va e'tibordan chetда qolishi oson — "Mavsum" so'zi butun mavsum degan taassurot beradi.

---

## 6. Boshqa joylarga ta'siri (item 6)

| Joy | Ta'sir |
|---|---|
| **Dashboard** ([dashboard.py:59](../backend/app/api/v1/routes/dashboard.py#L59)) | ❗ Xuddi shu. Dashboard "Mavsum" = 2026-09-01 … bugun. |
| **Rekord paneli** ([statistika.py:160](../backend/app/api/v1/routes/statistika.py#L160)) | ❗ "Eng yaxshi smena / eng yaxshi operator" — tanlangan davr uchun; "mavsum" da 2026-09-01 dan. **"Barcha vaqt eng yuqori kunlik yig'im"** ([statistika.py:197-204](../backend/app/api/v1/routes/statistika.py#L197-L204)) — sana filtri yo'q, TA'SIR QILMAYDI. |
| **Moliyaviy hisobot** ([moliyaviy.py:89](../backend/app/api/v1/routes/moliyaviy.py#L89)) | ❗ Xuddi shu qoida (`Partiya.sotuv_sanasi` bo'yicha). "Mavsum" moliyaviy hisobot 2026-09-01 dan. |
| **Mavsum jurnali Excel** ([hisobotlar.py:200](../backend/app/api/v1/routes/hisobotlar.py#L200)) | ⚠️ **BOSHQACHA.** Bu yagona joy `mavsum_boshlanish_sanasi` **sozlamasini** o'qiydi: `_mavsum_boshi_sozlamadan(db) or mavsum_boshlanishi(bugun)`. Sozlama = `2025-09-01` → Excel jurnal 2025-09-01 dan boshlaydi. |

### ➜ Ikkinchi (asosiy) nomuvofiqlik: "Mavsum" ikki xil ma'noda

| "Mavsum" qayerda | Boshlanish qanday aniqlanadi | Bugungi qiymat |
|---|---|---|
| Statistika ekrani, Dashboard, Rekord, Moliyaviy | `davr.py` qattiq qoidasi (har 1-sentyabr) | **2026-09-01** |
| Mavsum jurnali Excel (`/hisobotlar/mavsum-jurnali`) | `mavsum_boshlanish_sanasi` sozlamasi (fallback: qattiq qoida) | **2025-09-01** |

`mavsum_boshlanish_sanasi` sozlamasi seed default ([backend/scripts/seed.py:33](../backend/scripts/seed.py#L33)), tavsifi: *"Mavsum jurnali qaysi sanadan boshlanadi"*. Admin uni Sozlamalar ekranidan o'zgartirsa — **faqat Excel jurnal o'zgaradi**, Statistika/Dashboard/Rekord/Moliyaviy o'sha-o'sha 2026-09-01 da qoladi.

---

## 7. Verdikt

1. **"16" — backend kodi bo'yicha TO'G'RI son.** SQL, JOIN, GROUP BY, agregatsiya, pagination — hammasi soz. Har 4 mahsulot uchun backend soni oddiy SQL soni bilan aynan mos (16 / 6 / 1 / 1).
2. **Ildiz sabab:** [davr.py:6-27](../backend/app/services/davr.py#L6-L27) — "mavsum" har 1-sentyabrда nolга tushadigan joriy mavsum sifatida hisoblanadi. Bugun 2026-09-09 → oyna atigi 9 kunlik (2026-09-01 dan). Foydalanuvchining `>= 2025-09-01` so'rovi o'tgan mavsum oynasi. Farq = 2026-avgust kiplari (tola: 14 ta).
3. **Amaliy nomuvofiqlik:** bir xil "Mavsum" so'zi Statistika ekranida (2026-09-01) va Mavsum jurnali Excelida (2025-09-01, sozlamadan) turli sanalarni bildiradi. `mavsum_boshlanish_sanasi` sozlamasi Statistika/Dashboard/Rekord/Moliyaviy'ga **umuman ta'sir qilmaydi**.
4. **Qo'shimcha UX xavfi:** 1-sentyabrда Statistika/Dashboard "Mavsum" raqamlari ogohlantirishsiz ~65% ga tushdi — bu ma'lumot yo'qolgandek ko'rinadi (aynan shu foydalanuvchini chalg'itdi).

## 8. Tuzatish variantlari (audit doirasida — kod o'zgartirilmadi)

- **(A)** `davr_oraligi("mavsum", ...)` ham `mavsum_boshlanish_sanasi` sozlamasini o'qisin (db sessiyasini uzatish kerak bo'ladi) — shunda butun ilova bo'yicha "Mavsum" bitta ma'noda bo'ladi. `test_davr.py:25-32` yangilanishi kerak.
- **(B)** Agar 1-sentyabr avtomatik reset kerak bo'lsa — Statistika ekranida davr tugmasi ostida "Mavsum: 2026-09-01 dan" kabi ochiq yozuv qo'shilsin va `mavsum_boshlanish_sanasi` sozlamasi Sozlamalar ekranida "faqat Excel jurnal uchun" deb aniq belgilansin.
- **(C)** Ikkalasi: sozlamani hamma joyda ishlatish + davr oralig'ini ekranda ko'rsatish.
