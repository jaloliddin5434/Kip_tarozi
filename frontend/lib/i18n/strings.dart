enum Til { uz, ru }

const Map<String, Map<Til, String>> _matnlar = {
  'login_sarlavha': {Til.uz: 'Kip Tarozi', Til.ru: 'Kip Tarozi'},
  'login_belgi': {Til.uz: 'Login', Til.ru: 'Логин'},
  'parol_belgi': {Til.uz: 'Parol', Til.ru: 'Пароль'},
  'kirish': {Til.uz: 'Kirish', Til.ru: 'Войти'},
  'login_xato': {Til.uz: 'Login yoki parol noto\'g\'ri', Til.ru: 'Неверный логин или пароль'},

  'smena': {Til.uz: 'Smena', Til.ru: 'Смена'},
  'smena_holati': {Til.uz: 'Smena joriy holati', Til.ru: 'Текущее состояние смены'},
  'partiya_raqami': {Til.uz: 'Partiya raqami', Til.ru: 'Номер партии'},
  'partiya_raqami_kiriting': {Til.uz: 'Partiya raqamini kiriting', Til.ru: 'Введите номер партии'},
  'partiya_ochish': {Til.uz: 'Partiyani tanlash', Til.ru: 'Выбрать партию'},
  'partiya_majburiy': {Til.uz: 'Partiya raqami majburiy', Til.ru: 'Номер партии обязателен'},
  'ogirlik': {Til.uz: 'Og\'irlik (kg)', Til.ru: 'Вес (кг)'},
  'ogirlik_kiriting': {Til.uz: 'Og\'irlikni kiriting (RS232 simulyatsiyasi)', Til.ru: 'Введите вес (симуляция RS232)'},
  'saqlash': {Til.uz: 'Saqlash', Til.ru: 'Сохранить'},
  'bekor_qilish': {Til.uz: 'Bekor qilish', Til.ru: 'Отменить'},
  'kip_saqlandi': {Til.uz: 'Kip saqlandi', Til.ru: 'Кип сохранён'},
  'progress': {Til.uz: 'Joriy partiya', Til.ru: 'Текущая партия'},
  'soni': {Til.uz: 'soni', Til.ru: 'шт'},

  'dublikat_sarlavha': {Til.uz: 'Diqqat — ehtimol dublikat', Til.ru: 'Внимание — возможен дубликат'},
  'dublikat_matn': {
    Til.uz: 'Shunga o\'xshash og\'irlikdagi kip bir necha soniya oldin saqlangan. Bu haqiqatan ham yangi kipmi?',
    Til.ru: 'Кип с похожим весом был сохранён несколько секунд назад. Это действительно новый кип?',
  },
  'ha_yangi_kip': {Til.uz: 'Ha, yangi kip', Til.ru: 'Да, новый кип'},
  'yoq_bekor': {Til.uz: 'Yo\'q, bekor qilish', Til.ru: 'Нет, отменить'},

  'yuk_saqlanmadi_sarlavha': {Til.uz: '⚠️ YUK SAQLANMADI!', Til.ru: '⚠️ ГРУЗ НЕ СОХРАНЁН!'},
  'yuk_saqlanmadi_matn': {
    Til.uz: 'Tarozi ustiga yuk qo\'yildi, lekin saqlanmasdan olib qo\'yildi. Bu holat qayd etildi.',
    Til.ru: 'Груз был поставлен на весы, но убран без сохранения. Событие зафиксировано.',
  },
  'tushundim': {Til.uz: 'Tushundim', Til.ru: 'Понятно'},

  'tola': {Til.uz: 'Tola', Til.ru: 'Тола'},
  'lint': {Til.uz: 'Lint', Til.ru: 'Линт'},
  'pux': {Til.uz: 'Pux', Til.ru: 'Пух'},
  'ulyuk': {Til.uz: 'Ulyuk', Til.ru: 'Улюк'},

  'chiqish': {Til.uz: 'Chiqish', Til.ru: 'Выход'},
  'dashboard': {Til.uz: 'Bosh sahifa', Til.ru: 'Главная'},
  'hujjatlar': {Til.uz: 'Hujjatlar', Til.ru: 'Документы'},
  'statistika': {Til.uz: 'Statistika', Til.ru: 'Статистика'},
  'partiyalar': {Til.uz: 'Partiyalar', Til.ru: 'Партии'},

  'bugungi_statistika': {Til.uz: 'Bugungi statistika', Til.ru: 'Статистика за сегодня'},
  'ochiq_partiyalar': {Til.uz: 'Ochiq partiyalar', Til.ru: 'Открытые партии'},
  'shubhali_holatlar': {Til.uz: 'Tasdiqlanmagan shubhali holatlar', Til.ru: 'Неподтверждённые тревоги'},
  'agent_holati': {Til.uz: 'Stansiya agenti', Til.ru: 'Станционный агент'},
  'ulangan': {Til.uz: 'Ulangan', Til.ru: 'Подключён'},
  'ulanmagan': {Til.uz: 'Ulanmagan / noma\'lum', Til.ru: 'Не подключён / неизвестно'},

  'sana': {Til.uz: 'Sana', Til.ru: 'Дата'},
  'mahsulot': {Til.uz: 'Mahsulot', Til.ru: 'Продукт'},
  'operator': {Til.uz: 'Operator', Til.ru: 'Оператор'},
  'holati': {Til.uz: 'Holati', Til.ru: 'Статус'},
  'filtr': {Til.uz: 'Filtr', Til.ru: 'Фильтр'},
  'tozalash': {Til.uz: 'Tozalash', Til.ru: 'Очистить'},
  'jami': {Til.uz: 'Jami', Til.ru: 'Итого'},

  'davr_kunlik': {Til.uz: 'Kunlik', Til.ru: 'Дневной'},
  'davr_haftalik': {Til.uz: 'Haftalik', Til.ru: 'Недельный'},
  'davr_oylik': {Til.uz: 'Oylik', Til.ru: 'Месячный'},
  'davr_mavsum': {Til.uz: 'Mavsum', Til.ru: 'Сезон'},

  'sotildi': {Til.uz: 'Sotildi', Til.ru: 'Продано'},
  'sotilmagan': {Til.uz: 'Sotilmagan', Til.ru: 'Не продано'},
  'ochiq': {Til.uz: 'Ochiq', Til.ru: 'Открыта'},
  'yopiq': {Til.uz: 'Yopiq', Til.ru: 'Закрыта'},
  'yopish': {Til.uz: 'Yopish', Til.ru: 'Закрыть'},
  'sotish': {Til.uz: 'Sotildi deb belgilash', Til.ru: 'Отметить как продано'},
  'xaridor': {Til.uz: 'Xaridor', Til.ru: 'Покупатель'},
  'yuklanmoqda': {Til.uz: 'Yuklanmoqda...', Til.ru: 'Загрузка...'},
  'xatolik': {Til.uz: 'Xatolik yuz berdi', Til.ru: 'Произошла ошибка'},

  // Partiya "Sotildi" formasi
  'sort': {Til.uz: 'Sort', Til.ru: 'Сорт'},
  'urama_bilan_vazn': {Til.uz: 'Urama bilan vazn (kg)', Til.ru: 'Вес с упаковкой (кг)'},
  'urama_vazni': {Til.uz: 'Urama vazni (kg)', Til.ru: 'Вес упаковки (кг)'},
  'sof_vazn': {Til.uz: 'Sof vazn / netto (kg)', Til.ru: 'Чистый вес / нетто (кг)'},
  'kondicion_vazni': {Til.uz: 'Kondicion vazni (kg)', Til.ru: 'Кондиционный вес (кг)'},
  'bekor': {Til.uz: 'Bekor', Til.ru: 'Отмена'},

  // Hujjatlar jadvali
  'partiya': {Til.uz: 'Partiya', Til.ru: 'Партия'},
  'kip_qisqa': {Til.uz: 'Kip #', Til.ru: 'Кип №'},
  'kg': {Til.uz: 'kg', Til.ru: 'кг'},

  // Chop etish
  'chop_etish': {Til.uz: 'Chop etish', Til.ru: 'Печать'},
  'hujjat': {Til.uz: 'Hujjat', Til.ru: 'Документ'},
  'vaqt': {Til.uz: 'Vaqt', Til.ru: 'Время'},

  // Shubhali holatlar bo'limi
  'shubhali_holatlar_royxati': {Til.uz: 'Shubhali holatlar', Til.ru: 'Подозрительные события'},
  'korib_chiqildi': {Til.uz: 'Ko\'rib chiqildi', Til.ru: 'Рассмотрено'},
  'yangi': {Til.uz: 'Yangi', Til.ru: 'Новое'},
  'korib_chiqqan': {Til.uz: 'Ko\'rib chiqqan', Til.ru: 'Рассмотрел'},
  'sana_dan': {Til.uz: 'Sana dan', Til.ru: 'Дата с'},
  'sana_gacha': {Til.uz: 'Sana gacha', Til.ru: 'Дата по'},
  'smena_boyicha': {Til.uz: 'Smena bo\'yicha', Til.ru: 'По сменам'},

  // Moliyaviy bo'lim kirish ekrani
  'moliyaviy': {Til.uz: 'Moliyaviy', Til.ru: 'Финансы'},
  'moliyaviy_parol': {Til.uz: 'Moliyaviy parol', Til.ru: 'Финансовый пароль'},
  'moliyaviy_parol_tasdiqlash': {Til.uz: 'Parolni tasdiqlang', Til.ru: 'Подтвердите пароль'},
  'moliyaviy_parol_ornatish': {Til.uz: 'Parolni o\'rnatish', Til.ru: 'Установить пароль'},
  'moliyaviy_birinchi_marta_matni': {
    Til.uz: 'Moliyaviy bo\'lim uchun hali parol o\'rnatilmagan. Yangi parol yarating.',
    Til.ru: 'Пароль для финансового раздела ещё не установлен. Придумайте новый пароль.',
  },
  'parollar_mos_emas': {Til.uz: 'Parollar mos emas', Til.ru: 'Пароли не совпадают'},
  'moliyaviy_parol_notogri': {Til.uz: 'Moliyaviy parol noto\'g\'ri', Til.ru: 'Неверный финансовый пароль'},
  'moliyaviy_sessiya_tugadi': {
    Til.uz: 'Moliyaviy sessiya muddati tugadi, qaytadan kiring',
    Til.ru: 'Срок финансовой сессии истёк, войдите снова',
  },

  // Moliyaviy hisobot ekrani
  'uzex_narxlari': {Til.uz: 'UZEX narxlari', Til.ru: 'Цены UZEX'},
  'som': {Til.uz: 'so\'m', Til.ru: 'сум'},
};

class Lokalizatsiya {
  final Til til;
  const Lokalizatsiya(this.til);

  String t(String kalit) => _matnlar[kalit]?[til] ?? kalit;
}
