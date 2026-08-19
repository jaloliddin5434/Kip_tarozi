enum Til { uz, ru }

const Map<String, Map<Til, String>> _matnlar = {
  'login_sarlavha': {Til.uz: 'Kip Tarozi', Til.ru: 'Kip Tarozi'},
  'login_belgi': {Til.uz: 'Login', Til.ru: 'Логин'},
  'parol_belgi': {Til.uz: 'Parol', Til.ru: 'Пароль'},
  'kirish': {Til.uz: 'Kirish', Til.ru: 'Войти'},
  'login_xato': {
    Til.uz: 'Login yoki parol noto\'g\'ri',
    Til.ru: 'Неверный логин или пароль',
  },

  'smena': {Til.uz: 'Smena', Til.ru: 'Смена'},
  'smena_holati': {
    Til.uz: 'Smena joriy holati',
    Til.ru: 'Текущее состояние смены',
  },
  'partiya_raqami': {Til.uz: 'Partiya raqami', Til.ru: 'Номер партии'},
  'partiya_raqami_kiriting': {
    Til.uz: 'Partiya raqamini kiriting',
    Til.ru: 'Введите номер партии',
  },
  'partiya_ochish': {Til.uz: 'Partiyani tanlash', Til.ru: 'Выбрать партию'},
  'partiya_majburiy': {
    Til.uz: 'Partiya raqami majburiy',
    Til.ru: 'Номер партии обязателен',
  },
  'ogirlik': {Til.uz: 'Og\'irlik (kg)', Til.ru: 'Вес (кг)'},
  'ogirlik_kiriting': {
    Til.uz: 'Og\'irlikni kiriting (RS232 simulyatsiyasi)',
    Til.ru: 'Введите вес (симуляция RS232)',
  },
  'saqlash': {Til.uz: 'Saqlash', Til.ru: 'Сохранить'},
  'bekor_qilish': {Til.uz: 'Bekor qilish', Til.ru: 'Отменить'},
  'kip_saqlandi': {Til.uz: 'Kip saqlandi', Til.ru: 'Кип сохранён'},
  'progress': {Til.uz: 'Joriy partiya', Til.ru: 'Текущая партия'},
  'soni': {Til.uz: 'soni', Til.ru: 'шт'},

  'dublikat_sarlavha': {
    Til.uz: 'Diqqat — ehtimol dublikat',
    Til.ru: 'Внимание — возможен дубликат',
  },
  'dublikat_matn': {
    Til.uz:
        'Shunga o\'xshash og\'irlikdagi kip bir necha soniya oldin saqlangan. Bu haqiqatan ham yangi kipmi?',
    Til.ru:
        'Кип с похожим весом был сохранён несколько секунд назад. Это действительно новый кип?',
  },
  'ha_yangi_kip': {Til.uz: 'Ha, yangi kip', Til.ru: 'Да, новый кип'},
  'yoq_bekor': {Til.uz: 'Yo\'q, bekor qilish', Til.ru: 'Нет, отменить'},

  'yuk_saqlanmadi_sarlavha': {
    Til.uz: '⚠️ YUK SAQLANMADI!',
    Til.ru: '⚠️ ГРУЗ НЕ СОХРАНЁН!',
  },
  'yuk_saqlanmadi_matn': {
    Til.uz:
        'Tarozi ustiga yuk qo\'yildi, lekin saqlanmasdan olib qo\'yildi. Bu holat qayd etildi.',
    Til.ru:
        'Груз был поставлен на весы, но убран без сохранения. Событие зафиксировано.',
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

  'davr_statistikasi': {
    Til.uz: 'Davr statistikasi',
    Til.ru: 'Статистика за период',
  },
  'ochiq_partiyalar': {Til.uz: 'Ochiq partiyalar', Til.ru: 'Открытые партии'},
  'shubhali_holatlar': {
    Til.uz: 'Tasdiqlanmagan shubhali holatlar',
    Til.ru: 'Неподтверждённые тревоги',
  },
  'agent_holati': {Til.uz: 'Stansiya agenti', Til.ru: 'Станционный агент'},
  'ulangan': {Til.uz: 'Ulangan', Til.ru: 'Подключён'},
  'ulanmagan': {
    Til.uz: 'Ulanmagan / noma\'lum',
    Til.ru: 'Не подключён / неизвестно',
  },

  'sana': {Til.uz: 'Sana', Til.ru: 'Дата'},
  'mahsulot': {Til.uz: 'Mahsulot', Til.ru: 'Продукт'},
  'operator': {Til.uz: 'Operator', Til.ru: 'Оператор'},
  'holati': {Til.uz: 'Holati', Til.ru: 'Статус'},
  'filtr': {Til.uz: 'Filtr', Til.ru: 'Фильтр'},
  'tozalash': {Til.uz: 'Tozalash', Til.ru: 'Очистить'},
  'qidiruv': {Til.uz: 'Qidiruv', Til.ru: 'Поиск'},
  'qidiruv_maslahat': {
    Til.uz: 'Operator yoki partiya',
    Til.ru: 'Оператор или партия',
  },

  // Smena Excel hisoboti
  'excel_yuklab_olish': {Til.uz: 'Excel yuklab olish', Til.ru: 'Скачать Excel'},
  'excel_hisobot_tanlash': {
    Til.uz: 'Excel hisobotni tanlash',
    Til.ru: 'Выбор отчёта Excel',
  },
  'yuklab_olish': {Til.uz: 'Yuklab olish', Til.ru: 'Скачать'},
  'fayl_yuklab_olindi': {Til.uz: 'Fayl yuklab olindi', Til.ru: 'Файл скачан'},
  'jami': {Til.uz: 'Jami', Til.ru: 'Итого'},

  'davr_kunlik': {Til.uz: 'Kunlik', Til.ru: 'Дневной'},
  'davr_haftalik': {Til.uz: 'Haftalik', Til.ru: 'Недельный'},
  'davr_oylik': {Til.uz: 'Oylik', Til.ru: 'Месячный'},
  'davr_mavsum': {Til.uz: 'Mavsum', Til.ru: 'Сезон'},

  // Statistika ekrani
  'davr': {Til.uz: 'Davr', Til.ru: 'Период'},
  'ortacha_ogirlik': {Til.uz: 'O\'rtacha og\'irlik', Til.ru: 'Средний вес'},
  'smenalar_taqqoslash': {
    Til.uz: 'Smenalar taqqoslash',
    Til.ru: 'Сравнение смен',
  },
  'pdf_eksport': {Til.uz: 'PDF eksport', Til.ru: 'Экспорт в PDF'},
  'statistika_hujjati': {
    Til.uz: 'Statistika hisoboti',
    Til.ru: 'Отчёт по статистике',
  },
  'malumot_yoq': {
    Til.uz: 'Bu davr uchun ma\'lumot yo\'q',
    Til.ru: 'За этот период данных нет',
  },

  // Statistika — kalendar
  'kunlar_boyicha': {Til.uz: 'Kunlar bo\'yicha', Til.ru: 'По дням'},
  'oldingi_oy': {Til.uz: 'Oldingi oy', Til.ru: 'Предыдущий месяц'},
  'keyingi_oy': {Til.uz: 'Keyingi oy', Til.ru: 'Следующий месяц'},
  'kun_tanlang': {
    Til.uz: 'Tafsilotlarni ko\'rish uchun kalendardan bir kunni tanlang',
    Til.ru: 'Выберите день в календаре, чтобы увидеть детали',
  },
  'oy_1': {Til.uz: 'Yanvar', Til.ru: 'Январь'},
  'oy_2': {Til.uz: 'Fevral', Til.ru: 'Февраль'},
  'oy_3': {Til.uz: 'Mart', Til.ru: 'Март'},
  'oy_4': {Til.uz: 'Aprel', Til.ru: 'Апрель'},
  'oy_5': {Til.uz: 'May', Til.ru: 'Май'},
  'oy_6': {Til.uz: 'Iyun', Til.ru: 'Июнь'},
  'oy_7': {Til.uz: 'Iyul', Til.ru: 'Июль'},
  'oy_8': {Til.uz: 'Avgust', Til.ru: 'Август'},
  'oy_9': {Til.uz: 'Sentabr', Til.ru: 'Сентябрь'},
  'oy_10': {Til.uz: 'Oktabr', Til.ru: 'Октябрь'},
  'oy_11': {Til.uz: 'Noyabr', Til.ru: 'Ноябрь'},
  'oy_12': {Til.uz: 'Dekabr', Til.ru: 'Декабрь'},
  'hafta_1': {Til.uz: 'Du', Til.ru: 'Пн'},
  'hafta_2': {Til.uz: 'Se', Til.ru: 'Вт'},
  'hafta_3': {Til.uz: 'Ch', Til.ru: 'Ср'},
  'hafta_4': {Til.uz: 'Pa', Til.ru: 'Чт'},
  'hafta_5': {Til.uz: 'Ju', Til.ru: 'Пт'},
  'hafta_6': {Til.uz: 'Sh', Til.ru: 'Сб'},
  'hafta_7': {Til.uz: 'Ya', Til.ru: 'Вс'},

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
  'urama_bilan_vazn': {
    Til.uz: 'Urama bilan vazn (kg)',
    Til.ru: 'Вес с упаковкой (кг)',
  },
  'urama_vazni': {Til.uz: 'Urama vazni (kg)', Til.ru: 'Вес упаковки (кг)'},
  'sof_vazn': {
    Til.uz: 'Sof vazn / netto (kg)',
    Til.ru: 'Чистый вес / нетто (кг)',
  },
  'kondicion_vazni': {
    Til.uz: 'Kondicion vazni (kg)',
    Til.ru: 'Кондиционный вес (кг)',
  },
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
  'shubhali_holatlar_royxati': {
    Til.uz: 'Shubhali holatlar',
    Til.ru: 'Подозрительные события',
  },
  'korib_chiqildi': {Til.uz: 'Ko\'rib chiqildi', Til.ru: 'Рассмотрено'},
  'yangi': {Til.uz: 'Yangi', Til.ru: 'Новое'},
  'korib_chiqqan': {Til.uz: 'Ko\'rib chiqqan', Til.ru: 'Рассмотрел'},
  'sana_dan': {Til.uz: 'Sana dan', Til.ru: 'Дата с'},
  'sana_gacha': {Til.uz: 'Sana gacha', Til.ru: 'Дата по'},
  'smena_boyicha': {Til.uz: 'Smena bo\'yicha', Til.ru: 'По сменам'},
  'bugun': {Til.uz: 'Bugun', Til.ru: 'Сегодня'},

  // Moliyaviy bo'lim kirish ekrani
  'moliyaviy': {Til.uz: 'Moliyaviy', Til.ru: 'Финансы'},
  'moliyaviy_parol': {Til.uz: 'Moliyaviy parol', Til.ru: 'Финансовый пароль'},
  'moliyaviy_parol_tasdiqlash': {
    Til.uz: 'Parolni tasdiqlang',
    Til.ru: 'Подтвердите пароль',
  },
  'moliyaviy_parol_ornatish': {
    Til.uz: 'Parolni o\'rnatish',
    Til.ru: 'Установить пароль',
  },
  'moliyaviy_birinchi_marta_matni': {
    Til.uz:
        'Moliyaviy bo\'lim uchun hali parol o\'rnatilmagan. Yangi parol yarating.',
    Til.ru:
        'Пароль для финансового раздела ещё не установлен. Придумайте новый пароль.',
  },
  'parollar_mos_emas': {
    Til.uz: 'Parollar mos emas',
    Til.ru: 'Пароли не совпадают',
  },
  'moliyaviy_parol_notogri': {
    Til.uz: 'Moliyaviy parol noto\'g\'ri',
    Til.ru: 'Неверный финансовый пароль',
  },
  'moliyaviy_sessiya_tugadi': {
    Til.uz: 'Moliyaviy sessiya muddati tugadi, qaytadan kiring',
    Til.ru: 'Срок финансовой сессии истёк, войдите снова',
  },

  // Moliyaviy hisobot ekrani
  'uzex_narxlari': {Til.uz: 'UZEX narxlari', Til.ru: 'Цены UZEX'},
  'som': {Til.uz: 'so\'m', Til.ru: 'сум'},

  // Kip batafsil oynasi
  'kip_batafsil': {Til.uz: 'Kip haqida', Til.ru: 'О кипе'},
  'audit_tarixi': {Til.uz: 'O\'zgarishlar tarixi', Til.ru: 'История изменений'},
  'tahrirlash': {Til.uz: 'Tahrirlash', Til.ru: 'Редактировать'},
  'maydonlar_toldirilmagan': {
    Til.uz: 'Barcha maydonlarni to\'ldiring',
    Til.ru: 'Заполните все поля',
  },
  'sabab': {Til.uz: 'Sabab', Til.ru: 'Причина'},
  'surat': {Til.uz: 'Surat', Til.ru: 'Фото'},
  'surat_yoq': {Til.uz: 'Surat mavjud emas', Til.ru: 'Фото отсутствует'},
  'surat_yuklanmadi': {
    Til.uz: 'Rasm yuklanmadi',
    Til.ru: 'Не удалось загрузить фото',
  },
  'songgi_kip_surati': {
    Til.uz: 'So\'nggi tortilgan kip surati',
    Til.ru: 'Фото последнего кипа',
  },
  'hali_kip_saqlanmagan': {
    Til.uz: 'Hali kip saqlanmagan',
    Til.ru: 'Кип ещё не сохранён',
  },
  'yaratildi': {Til.uz: 'Yaratildi', Til.ru: 'Создано'},
  'tahrirlandi': {Til.uz: 'Tahrirlandi', Til.ru: 'Изменено'},
  'ochirildi': {Til.uz: 'O\'chirildi', Til.ru: 'Удалено'},
  'holati_aktiv': {Til.uz: 'Aktiv', Til.ru: 'Активен'},
  'holati_bekor_qilingan': {Til.uz: 'Bekor qilingan', Til.ru: 'Отменён'},
  'holati_tahrirlangan': {Til.uz: 'Tahrirlangan', Til.ru: 'Изменён'},
  'faqat_tahrirlangan': {
    Til.uz: 'Faqat tahrirlangan',
    Til.ru: 'Только изменённые',
  },
  'faqat_bekor_qilingan': {
    Til.uz: 'Faqat bekor qilingan',
    Til.ru: 'Только отменённые',
  },

  // Sozlamalar ekrani
  'sozlamalar': {Til.uz: 'Sozlamalar', Til.ru: 'Настройки'},
  'sozlama_saqlandi': {
    Til.uz: 'Sozlama saqlandi',
    Til.ru: 'Настройка сохранена',
  },
  'boshqa_sozlamalar': {
    Til.uz: 'Boshqa sozlamalar',
    Til.ru: 'Другие настройки',
  },
  'parolni_korsatish': {Til.uz: 'Ko\'rsatish', Til.ru: 'Показать'},
  'parolni_yashirish': {Til.uz: 'Yashirish', Til.ru: 'Скрыть'},
  'telegram_xatolik_bolimi': {
    Til.uz: 'Xatolik xabarnomalari (Telegram)',
    Til.ru: 'Уведомления об ошибках (Telegram)',
  },
  'telegram_xatolik_tavsif': {
    Til.uz:
        'Texnik xatoliklar (masalan "yuk saqlanmadi") shu Telegram botga yuboriladi',
    Til.ru:
        'Технические ошибки (например «груз не сохранён») отправляются в этот Telegram-бот',
  },
  'telegram_xatolik_bot_token': {Til.uz: 'Bot tokeni', Til.ru: 'Токен бота'},
  'telegram_xatolik_chat_id': {Til.uz: 'Chat ID', Til.ru: 'ID чата'},
  'telegram_statistika_bolimi': {
    Til.uz: 'Statistika xabarnomalari (Telegram)',
    Til.ru: 'Уведомления статистики (Telegram)',
  },
  'telegram_statistika_tavsif': {
    Til.uz:
        'Kunlik/smena statistik hisobotlari shu Telegram guruhiga yuboriladi',
    Til.ru:
        'Ежедневные/сменные статистические отчёты отправляются в эту Telegram-группу',
  },
  'telegram_statistika_bot_token': {Til.uz: 'Bot tokeni', Til.ru: 'Токен бота'},
  'telegram_statistika_chat_id': {Til.uz: 'Chat ID', Til.ru: 'ID чата'},

  // Partiya sort/og'irlik to'ldirish (Tayyor mahsulotlar bo'limi)
  'sort_ogirlik_toldirish': {
    Til.uz: 'Sort/og\'irlik to\'ldirish',
    Til.ru: 'Заполнить сорт/вес',
  },

  // Login ekrani — rol tanlash
  'rolni_tanlang': {Til.uz: 'Rolingizni tanlang', Til.ru: 'Выберите свою роль'},
  'admin_rol': {Til.uz: 'Admin', Til.ru: 'Администратор'},
  'tayyor_mahsulotlar_rol': {
    Til.uz: 'Tayyor mahsulotlar bo\'limi',
    Til.ru: 'Отдел готовой продукции',
  },
  'orqaga': {Til.uz: 'Orqaga', Til.ru: 'Назад'},
  'smenani_tanlang': {Til.uz: 'Smenani tanlang', Til.ru: 'Выберите смену'},

  // Operator ekrani — qayta dizayn
  'server': {Til.uz: 'Server', Til.ru: 'Сервер'},
  'kamera': {Til.uz: 'Kamera', Til.ru: 'Камера'},
  'tarozi': {Til.uz: 'Tarozi', Til.ru: 'Весы'},
  'barqaror': {Til.uz: 'Barqaror', Til.ru: 'Стабильно'},
  'kutilmoqda': {Til.uz: 'Kutilmoqda...', Til.ru: 'Ожидание...'},
  'song_ishlatilganlar': {
    Til.uz: 'So\'nggi ishlatilganlar',
    Til.ru: 'Недавно использованные',
  },
  'oxirgi_tortishlar': {
    Til.uz: 'Oxirgi tortishlar',
    Til.ru: 'Последние взвешивания',
  },
  'smena_tarixi': {Til.uz: 'Smena tarixi', Til.ru: 'История смены'},
  'tarix_yoq': {
    Til.uz: 'Bu mahsulot bo\'yicha hali tortishlar yo\'q',
    Til.ru: 'По этому продукту пока нет взвешиваний',
  },

  // Partiyalar ekrani — kartalar ko'rinishi
  'barchasi': {Til.uz: 'Barchasi', Til.ru: 'Все'},
  'yaratilgan_sana': {Til.uz: 'Yaratilgan sana', Til.ru: 'Дата создания'},
  'sotilgan_sana': {Til.uz: 'Sotilgan sana', Til.ru: 'Дата продажи'},
  'nakladnoy': {Til.uz: 'Nakladnoy', Til.ru: 'Накладная'},
  'partiyalar_qidiruv_maslahat': {
    Til.uz: 'Mahsulot, partiya raqami yoki xaridor',
    Til.ru: 'Продукт, номер партии или покупатель',
  },
  'partiyalar_topilmadi': {
    Til.uz: 'Partiyalar topilmadi',
    Til.ru: 'Партии не найдены',
  },

  // Partiya batafsil oynasi
  'partiya_batafsil': {Til.uz: 'Partiya haqida', Til.ru: 'О партии'},
  'yopilgan_sana': {Til.uz: 'Yopilgan sana', Til.ru: 'Дата закрытия'},
  'dogovor_raqami': {Til.uz: 'Dogovor raqami', Til.ru: 'Номер договора'},
  'kip_soni': {Til.uz: 'Kip soni', Til.ru: 'Количество кипов'},
  'jami_ogirlik': {Til.uz: 'Jami og\'irlik', Til.ru: 'Общий вес'},
  'partiyadagi_kiplar': {
    Til.uz: 'Ushbu partiyadagi kiplar',
    Til.ru: 'Кипы этой партии',
  },
  'kiplar_topilmadi': {Til.uz: 'Kiplar topilmadi', Til.ru: 'Кипы не найдены'},
  'nakladnoy_yuklab_olish': {
    Til.uz: 'Nakladnoy PDF\'ni yuklab olish',
    Til.ru: 'Скачать PDF накладной',
  },
};

class Lokalizatsiya {
  final Til til;
  const Lokalizatsiya(this.til);

  String t(String kalit) => _matnlar[kalit]?[til] ?? kalit;
}
