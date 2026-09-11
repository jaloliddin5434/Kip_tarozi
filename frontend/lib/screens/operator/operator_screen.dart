import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../models/mahsulot.dart';
import '../../models/partiya.dart';
import '../../models/smena_holati.dart';
import '../../services/fayl_yuklab_olish.dart';
import '../../services/kamera_agent.dart';
import '../../services/offline_kip_navbati.dart';
import '../../services/offline_surat.dart';
import '../../services/surat_sarlavhalari.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/clock_widget.dart';
import '../../widgets/kamera_tasdiq_kutish_dialog.dart';
import '../../widgets/kip_togrilash_dialogi.dart';
import '../../widgets/smena_kalendar_dialogi.dart';
import '../../widgets/yuk_saqlanmadi_dialog.dart';

const _uuid = Uuid();

/// Partiyaning "to'lgan" deb hisoblanadigan nishon (target) kip soni —
/// Tola uchun 220, qolgan mahsulotlar uchun 210.
const _nishonSoni = {'tola': 220, 'lint': 210, 'pux': 210, 'ulyuk': 210};

int _nishon(String mahsulotKodi) => _nishonSoni[mahsulotKodi] ?? 210;

/// O'RTA ustundagi og'irlik ko'rsatkichi qutisi uchun QAT'IY balandlik —
/// "imkon qadar katta" emas, o'zgarmas konstanta. (Surat paneli avval ham shu
/// balandlikda edi, endi u mustaqil ravishda Expanded bilan kattaroq — qarang
/// _ongPanel. Bu yerda faqat og'irlik qutisi qat'iy qoladi.)
const _panelBalandligi = 270.0;

class OperatorEkrani extends StatefulWidget {
  const OperatorEkrani({super.key});

  @override
  State<OperatorEkrani> createState() => _OperatorEkraniState();
}

class _OperatorEkraniState extends State<OperatorEkrani> {
  List<Mahsulot> _mahsulotlar = [];
  Mahsulot? _tanlanganMahsulot;
  List<Partiya> _ochiqPartiyalar = [];
  Partiya? _tanlanganPartiya;
  SmenaHolati? _smenaHolati;

  final _partiyaRaqamiKontrolleri = TextEditingController();
  final _ogirlikKontrolleri = TextEditingController();
  final _ogirlikFokusi = FocusNode();

  bool _partiyaYuklanmoqda = false;
  bool _saqlashYuklanmoqda = false;
  bool _excelYuklanmoqda = false;
  bool _mahsulotExcelYuklanmoqda = false;
  Map<String, dynamic>? _oxirgiSaqlanganKip;

  // Og'irlik ko'rsatkichining rang-signal holati: tarozida yuk bormi (yashil)
  // yoki yo'qmi (qizil). Saqlash bosilgandan keyin maydon tozalanadi, lekin
  // signal yashil bo'lib qolishi kerak — shuning uchun bu holat alohida
  // saqlanadi, faqat _ogirlikKontrolleri matnidan har safar hisoblanmaydi.
  bool _yukBor = false;
  bool _dasturiyTozalash = false;

  bool _smenaRoyxatiYuklanmoqda = false;
  List<Map<String, dynamic>> _smenaRoyxati = [];

  // Shu sessiya davomida operator ishlatgan partiya raqamlari, mahsulot kodi
  // bo'yicha (eng yangisi birinchi) — backend'da alohida saqlanmaydi, faqat
  // qulaylik uchun frontend xotirasida kuzatiladi.
  final Map<String, List<int>> _songiPartiyalar = {};

  // _partiyaniOchish() har chaqirilganda oshiriladigan so'rov hisoblagichi —
  // operator tez-tez turli partiya raqamlarini kiritib bossa, oldingi
  // (sekinroq) so'rovning javobi keyingi (tezroq) javobdan KEYIN kelib
  // qolishi mumkin. Javob qaytganda shu ID hozirgi (eng oxirgi) qiymatga
  // teng bo'lmasa — bu eskirgan (stale) javob, e'tiborsiz qoldiriladi.
  int _partiyaOchishSorovId = 0;

  Timer? _blokTimer;
  bool _blokDialogiKorinmoqda = false;

  // Kamera ishlamasa — Admin ruxsatini kutish (POST /kiplar -> 202).
  bool _kameraTasdiqKutilmoqda = false;
  Timer? _kameraTasdiqPoll;

  // Saqlash bosilgandan keyin 3 soniyalik oddiy kutish — tezkor ketma-ket
  // xato bosishning oldini oladi. Avvalgi 30s "Bekor qilish" hisoblagichi
  // butunlay olib tashlandi, backend endpointi (/kiplar/{id}/bekor-qilish)
  // esa admin panel uchun saqlanib qoldi, faqat shu yerdan chaqirilmaydi.
  bool _saqlashVaqtinchaNofaol = false;
  Timer? _saqlashQulfTaymeri;

  // Offline (lokal) navbat: internet/server uzilganda saqlangan, hali
  // yuborilmagan kiplar soni. > 0 bo'lsa AppBar'da indikator ko'rinadi.
  int _navbatUzunligi = 0;
  bool _navbatSinxronlanmoqda = false;
  Timer? _navbatTaymeri;

  // Offline surat uchun Stansiya Agenti (localhost) manzili — backend beradi,
  // kamera login/parol EMAS. null bo'lsa offline surat olinmaydi (kip suratsiz).
  String? _agentSuratUrl;

  @override
  void initState() {
    super.initState();
    _boshlangichniYuklash();
    _blokTimer = Timer.periodic(const Duration(seconds: 5), (_) => _blokniTekshirish());
    _navbatUzunliginiYangilash();
    _navbatTaymeri = Timer.periodic(const Duration(seconds: 10), (_) => _navbatniSinxronla());
    _ogirlikKontrolleri.addListener(_ogirlikOzgardi);
  }

  @override
  void dispose() {
    _blokTimer?.cancel();
    _navbatTaymeri?.cancel();
    _saqlashQulfTaymeri?.cancel();
    _kameraTasdiqPoll?.cancel();
    _ogirlikKontrolleri.removeListener(_ogirlikOzgardi);
    _partiyaRaqamiKontrolleri.dispose();
    _ogirlikKontrolleri.dispose();
    _ogirlikFokusi.dispose();
    super.dispose();
  }

  void _ogirlikOzgardi() {
    // Dasturiy tozalash (saqlashdan keyin) signalni qizilga qaytarmasligi
    // kerak — faqat operatorning o'zi kiritgan/tozalagan holatlarda signal
    // qayta hisoblanadi.
    if (!_dasturiyTozalash) {
      final qiymat = double.tryParse(_ogirlikKontrolleri.text.replaceAll(',', '.'));
      _yukBor = qiymat != null && qiymat > 0;
    }
    if (mounted) setState(() {});
  }

  AppState get _holat => context.read<AppState>();

  Future<void> _boshlangichniYuklash() async {
    try {
      final mahsulotlarJavob = await _holat.api.get('/mahsulotlar');
      setState(() => _mahsulotlar = (mahsulotlarJavob as List).map((e) => Mahsulot.fromJson(e)).toList());
      await _smenaHolatiniYangilash();
      await _blokniTekshirish();
    } catch (e) {
      _xatoKorsat(e.toString());
    }
    await _kameraSozlamalariniYukla();
  }

  /// Offline surat uchun — backend LAN kamerasi manzilini (Stansiya Agenti
  /// localhost URL'i) beradi. Faqat MANZIL, kamera login/parol EMAS. Backend
  /// hozir ulanmasa jimgina o'tkazib yuboriladi (keyingi sinxronда qayta olinadi).
  Future<void> _kameraSozlamalariniYukla() async {
    try {
      final javob = await _holat.api.get('/kiplar/kamera-sozlamalari').timeout(const Duration(seconds: 5));
      final url = (javob as Map)['agent_surat_url'] as String?;
      if (mounted) setState(() => _agentSuratUrl = url);
    } catch (_) {
      // Backend ulanmasa — _agentSuratUrl null qoladi, keyingi urinishda olinadi.
    }
  }

  Future<void> _smenaHolatiniYangilash() async {
    try {
      final javob = await _holat.api.get('/kiplar/smena/holati');
      if (mounted) setState(() => _smenaHolati = SmenaHolati.fromJson(javob));
    } catch (_) {
      // Jimgina o'tkazib yuboriladi — bosh sahifa ma'lumoti hal qiluvchi emas
    }
  }

  Future<void> _blokniTekshirish() async {
    try {
      final javob = await _holat.api.get('/shubhali-holatlar/bloklovchi');
      if (javob != null && !_blokDialogiKorinmoqda && mounted) {
        _blokDialogiKorinmoqda = true;
        await yukSaqlanmadiDialogniKorsat(
          context: context,
          lok: _holat.lok,
          onTushundim: () async {
            try {
              await _holat.api.patch('/shubhali-holatlar/${javob['id']}/tasdiqla');
            } catch (e) {
              _xatoKorsat(e.toString());
            }
          },
        );
        _blokDialogiKorinmoqda = false;
      }
    } catch (_) {
      // Aloqa muammosi — keyingi tsiklda qayta uriniladi
    }

    // Kamera tasdiq so'rovi (kutilayotgan) bo'lsa — operatorni qayta bloklaymiz.
    // Ilova qayta ochilsa yoki dialog qandaydir yo'l bilan yopilsa ham blok
    // shu tekshiruv orqali tiklanadi.
    try {
      final k = await _holat.api.get('/kamera-tasdiq/mening-kutilayotganim');
      if (k != null && !_kameraTasdiqKutilmoqda && mounted) {
        await _kameraTasdiginiKut(k['id'] as int);
      }
    } catch (_) {
      // Aloqa muammosi — keyingi tsiklda qayta
    }
  }

  /// Kamera surat ololmadi (POST /kiplar -> HTTP 202): operator TO'LIQ
  /// bloklanadi, Admin (panel yoki Telegram tugmasi) tasdiqlash/rad etguncha.
  /// Har 3 soniyada holat so'raladi — tasdiqlansa kip saqlangan hisoblanadi
  /// va ekran avtomatik davom etadi; rad etilsa operator qaytadan urinadi.
  Future<void> _kameraTasdiginiKut(int sorovId) async {
    if (_kameraTasdiqKutilmoqda) return;
    _kameraTasdiqKutilmoqda = true;

    final tugadi = Completer<String>(); // 'tasdiqlangan' | 'rad_etilgan'
    String? izoh;

    _kameraTasdiqPoll?.cancel();
    _kameraTasdiqPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final h = await _holat.api.get('/kamera-tasdiq/$sorovId/holat');
        final holati = h['holati'] as String?;
        if (holati == 'tasdiqlangan' || holati == 'rad_etilgan') {
          izoh = h['izoh'] as String?;
          _kameraTasdiqPoll?.cancel();
          if (!tugadi.isCompleted) tugadi.complete(holati);
        }
      } catch (_) {
        // tarmoq muammosi — keyingi tsiklda qayta
      }
    });

    if (mounted) {
      await kameraTasdiqKutishDialogniKorsat(
        context: context,
        lok: _holat.lok,
        tugash: tugadi.future,
      );
    }
    _kameraTasdiqPoll?.cancel();
    _kameraTasdiqKutilmoqda = false;

    if (!tugadi.isCompleted) return;
    final natija = await tugadi.future;
    if (!mounted) return;
    final lok = _holat.lok;

    if (natija == 'tasdiqlangan') {
      _dasturiyTozalash = true;
      _ogirlikKontrolleri.clear();
      _dasturiyTozalash = false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lok.t('kamera_tasdigi_tasdiqlandi'))));
      _ogirlikFokusi.requestFocus();
      await _smenaHolatiniYangilash();
      await _ochiqPartiyalarniYangilash();
      await _smenaRoyxatiniYangilash();
    } else if (natija == 'rad_etilgan') {
      final matn = (izoh == null || izoh!.isEmpty)
          ? lok.t('kamera_tasdigi_rad_etildi')
          : '${lok.t('kamera_tasdigi_rad_etildi')} — $izoh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(matn), backgroundColor: Colors.orange.shade800, duration: const Duration(seconds: 5)),
      );
    }
  }

  Future<void> _mahsulotTanlash(Mahsulot mahsulot) async {
    setState(() {
      _tanlanganMahsulot = mahsulot;
      _tanlanganPartiya = null;
      _ochiqPartiyalar = [];
      _partiyaRaqamiKontrolleri.clear();
      _smenaRoyxati = [];
      _yukBor = false;
    });
    await Future.wait([_ochiqPartiyalarniYangilash(), _smenaRoyxatiniYangilash()]);
  }

  /// Tanlangan mahsulot bo'yicha, joriy smenada, bugun tortilgan kiplar
  /// ro'yxatini yuklaydi — o'ng ustundagi "Smena tarixi" panelini to'ldirish
  /// uchun.
  Future<void> _smenaRoyxatiniYangilash() async {
    final soralganMahsulot = _tanlanganMahsulot;
    if (soralganMahsulot == null) return;
    setState(() => _smenaRoyxatiYuklanmoqda = true);
    try {
      final javob = await _holat.api.get('/kiplar/smena/royxat', query: {'mahsulot_kodi': soralganMahsulot.kod});
      // Operator javob kutilayotganda boshqa mahsulotga o'tib ketgan bo'lishi
      // mumkin — eskirgan javobni e'tiborsiz qoldiramiz.
      if (_tanlanganMahsulot?.id != soralganMahsulot.id) return;
      setState(() => _smenaRoyxati = (javob as List).cast<Map<String, dynamic>>());
    } catch (e) {
      _xatoKorsat(e.toString());
    } finally {
      if (mounted && _tanlanganMahsulot?.id == soralganMahsulot.id) {
        setState(() => _smenaRoyxatiYuklanmoqda = false);
      }
    }
  }

  /// Kip saqlangandan keyin partiya progressini (kip_soni/jami_kg) yangilaydi —
  /// _mahsulotTanlash'dan farqli, joriy tanlangan partiyani BEKOR QILMAYDI,
  /// aks holda operator har kip saqlagandan keyin partiya raqamini qayta
  /// kiritishga majbur bo'lardi.
  Future<void> _ochiqPartiyalarniYangilash() async {
    final soralganMahsulot = _tanlanganMahsulot;
    if (soralganMahsulot == null) return;
    try {
      final javob = await _holat.api.get('/partiyalar/ochiq', query: {'mahsulot_kodi': soralganMahsulot.kod});
      // Operator javob kutilayotganda boshqa mahsulotga o'tib ketgan bo'lishi
      // mumkin — bunday holda eskirgan javobni e'tiborsiz qoldiramiz, aks
      // holda ro'yxat boshqa mahsulotning partiyalari bilan aralashib qoladi.
      if (_tanlanganMahsulot?.id != soralganMahsulot.id) return;
      final yangilangan = (javob as List).map((e) => Partiya.fromJson(e)).toList();
      setState(() {
        _ochiqPartiyalar = yangilangan;
        if (_tanlanganPartiya != null) {
          final mos = yangilangan.where((p) => p.id == _tanlanganPartiya!.id);
          if (mos.isNotEmpty) _tanlanganPartiya = mos.first;
        }
      });
    } catch (e) {
      _xatoKorsat(e.toString());
    }
  }

  Future<void> _partiyaniOchish() async {
    final matn = _partiyaRaqamiKontrolleri.text.trim();
    if (_tanlanganMahsulot == null) return;
    if (matn.isEmpty) {
      _xatoKorsat(_holat.lok.t('partiya_majburiy'));
      return;
    }
    final raqam = int.tryParse(matn);
    if (raqam == null || raqam < 1) {
      _xatoKorsat(_holat.lok.t('partiya_majburiy'));
      return;
    }

    final soralganId = ++_partiyaOchishSorovId;
    setState(() => _partiyaYuklanmoqda = true);
    try {
      final javob = await _holat.api
          .post('/partiyalar', tana: {'mahsulot_kodi': _tanlanganMahsulot!.kod, 'partiya_raqami': raqam});
      // Operator javob kutilayotganda boshqa partiya raqamini yuborgan
      // bo'lishi mumkin — bunday holda eskirgan javobni e'tiborsiz
      // qoldiramiz, aks holda oxirgi so'ralgan partiya o'rniga eski partiya
      // saqlanib qolib, keyingi tortish NOTO'G'RI partiyaga yozilib qolishi
      // mumkin edi.
      if (soralganId != _partiyaOchishSorovId) return;
      final partiya = Partiya.fromJson(javob);
      setState(() {
        _tanlanganPartiya = partiya;
        if (!_ochiqPartiyalar.any((p) => p.id == partiya.id)) _ochiqPartiyalar = [..._ochiqPartiyalar, partiya];
        _songiPartiyaniEslash(partiya.mahsulotKodi, partiya.partiyaRaqami);
      });
      _ogirlikFokusi.requestFocus();
    } catch (e) {
      if (soralganId != _partiyaOchishSorovId) return;
      _xatoKorsat(e.toString());
    } finally {
      if (mounted && soralganId == _partiyaOchishSorovId) setState(() => _partiyaYuklanmoqda = false);
    }
  }

  void _songiPartiyaniEslash(String mahsulotKodi, int raqam) {
    final royxat = _songiPartiyalar.putIfAbsent(mahsulotKodi, () => []);
    royxat.remove(raqam);
    royxat.insert(0, raqam);
    if (royxat.length > 5) royxat.removeRange(5, royxat.length);
  }

  void _partiyaniTanlash(Partiya partiya) {
    setState(() {
      _tanlanganPartiya = partiya;
      _partiyaRaqamiKontrolleri.text = partiya.partiyaRaqami.toString();
    });
    _ogirlikFokusi.requestFocus();
  }

  void _songiPartiyaTanlandi(int raqam) {
    _partiyaRaqamiKontrolleri.text = raqam.toString();
    _partiyaniOchish();
  }

  Future<void> _saqlash({bool majburiy = false}) async {
    if (_tanlanganPartiya == null) {
      _xatoKorsat(_holat.lok.t('partiya_majburiy'));
      return;
    }
    final ogirlik = double.tryParse(_ogirlikKontrolleri.text.replaceAll(',', '.'));
    if (ogirlik == null || ogirlik <= 0) {
      _xatoKorsat(_holat.lok.t('ogirlik_kiriting'));
      return;
    }

    setState(() => _saqlashYuklanmoqda = true);
    final tana = {
      'mijoz_id': _uuid.v4(),
      'partiya_id': _tanlanganPartiya!.id,
      'ogirlik': ogirlik,
      'mahalliy_vaqt': DateTime.now().toUtc().toIso8601String(),
      'majburiy': majburiy,
      if (ApiClient.stansiyaId != null) 'stansiya_id': ApiClient.stansiyaId,
    };

    try {
      dynamic javob;
      try {
        // 8s timeout — noto'g'ri portga/yetib bo'lmaydigan hostga ulanishda ham
        // "offline" holatiga tez o'tish uchun.
        javob = await _holat.api.post('/kiplar', tana: tana).timeout(const Duration(seconds: 8));
      } on ApiException catch (e) {
        // Server JAVOB BERDI (validatsiya/biznes xatosi) — bu haqiqiy xato,
        // lokal navbatga saqlanmaydi.
        if (e.statusCode == 409 && e.tafsilot is Map && e.tafsilot['avvalgi_kip_id'] != null) {
          _dublikatOgohlantirishKorsat();
        } else {
          _xatoKorsat(e.xabar);
        }
        return;
      } catch (_) {
        // ApiException EMAS => ulanish/timeout muammosi => lokal navbatga.
        await _lokalNavbatgaSaqla(tana);
        return;
      }

      // Kamera SOZLANGAN, lekin surat OLINMADI (HTTP 202) — kip saqlanmadi.
      // Operator TO'LIQ bloklanadi, Admin ruxsatini kutadi.
      if (javob is Map && javob['kamera_tasdiq_kutilmoqda'] == true) {
        await _kameraTasdiginiKut(javob['sorov_id'] as int);
        return;
      }

      // --- Muvaffaqiyatli saqlandi ---
      if (!mounted) return;
      _dasturiyTozalash = true;
      _ogirlikKontrolleri.clear();
      _dasturiyTozalash = false;
      setState(() {
        _oxirgiSaqlanganKip = javob;
        _saqlashVaqtinchaNofaol = true;
      });
      _saqlashQulfTaymeri?.cancel();
      _saqlashQulfTaymeri = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saqlashVaqtinchaNofaol = false);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_holat.lok.t('kip_saqlandi'))));
      _ogirlikFokusi.requestFocus();
      await _smenaHolatiniYangilash();
      await _ochiqPartiyalarniYangilash();
      await _smenaRoyxatiniYangilash();
    } finally {
      if (mounted) setState(() => _saqlashYuklanmoqda = false);
    }
  }

  /// Tarmoq xatosi tufayli kip lokal navbatga yoziladi — operator bloklanmaydi,
  /// ish davom etadi, fon jarayoni aloqa tiklangach avtomatik yuboradi.
  ///
  /// Surat: backend uzilgan bo'lsa ham kamera LOKAL TARMOQDA — Stansiya Agenti
  /// (localhost) orqali bitta kadr olishga urinamiz va uni kip bilan birga
  /// navbatga qo'yamiz. Agent/kamera ham o'chgan bo'lsa — kip suratsiz saqlanadi.
  Future<void> _lokalNavbatgaSaqla(Map<String, dynamic> tana) async {
    final lok = _holat.lok;
    final mijozId = tana['mijoz_id'] as String;

    String? suratYoli;
    final agentUrl = _agentSuratUrl;
    if (agentUrl != null) {
      final baytlar = await agentdanSurat(agentUrl);
      if (baytlar != null) suratYoli = await suratniSaqla(baytlar, mijozId);
    }

    await OfflineKipNavbati.qoshish(tana: tana, token: _holat.api.token ?? '', suratYoli: suratYoli);
    if (!mounted) return;
    _dasturiyTozalash = true;
    _ogirlikKontrolleri.clear();
    _dasturiyTozalash = false;
    _saqlashQulfTaymeri?.cancel();
    setState(() => _saqlashVaqtinchaNofaol = true);
    _saqlashQulfTaymeri = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saqlashVaqtinchaNofaol = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lok.t(suratYoli != null ? 'offline_lokal_saqlandi_surat' : 'offline_lokal_saqlandi')),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
    _ogirlikFokusi.requestFocus();
    await _navbatUzunliginiYangilash();
  }

  Future<void> _navbatUzunliginiYangilash() async {
    final n = await OfflineKipNavbati.uzunlik();
    if (mounted && n != _navbatUzunligi) setState(() => _navbatUzunligi = n);
  }

  /// Fon jarayoni (har 10s) — navbatda kutilayotgan yozuvlarni backend'ga
  /// yuborishga urinadi, muvaffaqiyatlilarni navbatdan o'chiradi.
  Future<void> _navbatniSinxronla() async {
    if (_navbatSinxronlanmoqda || !_holat.kirilgan) return;
    if (await OfflineKipNavbati.uzunlik() == 0) {
      await _navbatUzunliginiYangilash();
      return;
    }
    if (!mounted) return;
    setState(() => _navbatSinxronlanmoqda = true);
    final lok = _holat.lok;
    final xabarchi = ScaffoldMessenger.of(context);
    try {
      // Backend qayta ulangan bo'lsa va agent manzilini hali olmagan bo'lsak — olamiz.
      if (_agentSuratUrl == null) await _kameraSozlamalariniYukla();
      final natija = await OfflineKipNavbati.sinxronla(_holat.api);
      if (!mounted) return;
      await _navbatUzunliginiYangilash();
      if (natija.yuborilgan > 0) {
        xabarchi.showSnackBar(
          SnackBar(content: Text('${natija.yuborilgan} ${lok.t('navbat_yuborildi')}')),
        );
        await _smenaHolatiniYangilash();
        await _ochiqPartiyalarniYangilash();
        await _smenaRoyxatiniYangilash();
      }
      // Sinxronlangan (surat bilan) oxirgi kipni "so'nggi kip surati" panelida ko'rsat.
      if (natija.songgiKipId != null) await _sinxronlanganKipniKorsat(natija.songgiKipId!);
      for (final xato in natija.xatolar) {
        _xatoKorsat('${lok.t('navbat_yuborilmadi')}: $xato');
      }
    } finally {
      if (mounted) setState(() => _navbatSinxronlanmoqda = false);
    }
  }

  /// Offline navbatdan sinxronlangan kip ma'lumotini (surat bilan) olib,
  /// "so'nggi tortilgan kip surati" panelida ko'rsatadi.
  Future<void> _sinxronlanganKipniKorsat(int kipId) async {
    try {
      final javob = await _holat.api.get('/kiplar/$kipId');
      if (mounted) setState(() => _oxirgiSaqlanganKip = (javob as Map).cast<String, dynamic>());
    } catch (_) {
      // muhim emas — panel eski holatida qoladi
    }
  }

  void _dublikatOgohlantirishKorsat() {
    final lok = _holat.lok;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lok.t('dublikat_sarlavha')),
        content: Text(lok.t('dublikat_matn')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(lok.t('yoq_bekor'))),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _saqlash(majburiy: true);
            },
            child: Text(lok.t('ha_yangi_kip')),
          ),
        ],
      ),
    );
  }

  Future<void> _excelYuklab() async {
    final smena = _holat.foydalanuvchi?.smena;
    if (smena == null) return;

    setState(() => _excelYuklanmoqda = true);
    try {
      final sana = DateTime.now().toIso8601String().substring(0, 10);
      final baytlar = await _holat.api.getBaytlar('/hisobotlar/smena-excel', query: {'sana': sana, 'smena': smena});
      final yol = await faylniSaqlash(baytlar, 'Smena_${smena}_$sana.xlsx');
      if (mounted) {
        final lok = _holat.lok;
        final xabar = yol == null ? lok.t('fayl_yuklab_olindi') : '${lok.t('fayl_saqlandi')}: $yol';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(xabar)));
      }
    } on ApiException catch (e) {
      _xatoKorsat(e.xabar);
    } catch (e) {
      _xatoKorsat('${_holat.lok.t('fayl_saqlash_xatosi')}: $e');
    } finally {
      if (mounted) setState(() => _excelYuklanmoqda = false);
    }
  }

  /// Tanlangan mahsulot uchun tor eksport — faqat bugungi kun + operatorning
  /// o'z smenasi + shu mahsulot bo'yicha kiplar ro'yxati (backend:
  /// /hisobotlar/smena-mahsulot-excel).
  Future<void> _mahsulotExcelYuklab() async {
    final smena = _holat.foydalanuvchi?.smena;
    final mahsulot = _tanlanganMahsulot;
    if (smena == null || mahsulot == null) return;

    setState(() => _mahsulotExcelYuklanmoqda = true);
    try {
      final sana = DateTime.now().toIso8601String().substring(0, 10);
      final baytlar = await _holat.api.getBaytlar(
        '/hisobotlar/smena-mahsulot-excel',
        query: {'sana': sana, 'smena': smena, 'mahsulot_kodi': mahsulot.kod},
      );
      final nom = mahsulot.nomi.replaceAll(' ', '_');
      final yol = await faylniSaqlash(baytlar, 'Smena_${smena}_${nom}_$sana.xlsx');
      if (mounted) {
        final lok = _holat.lok;
        final xabar = yol == null ? lok.t('fayl_yuklab_olindi') : '${lok.t('fayl_saqlandi')}: $yol';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(xabar)));
      }
    } on ApiException catch (e) {
      _xatoKorsat(e.xabar);
    } catch (e) {
      _xatoKorsat('${_holat.lok.t('fayl_saqlash_xatosi')}: $e');
    } finally {
      if (mounted) setState(() => _mahsulotExcelYuklanmoqda = false);
    }
  }

  void _xatoKorsat(String xabar) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(xabar), backgroundColor: Colors.red.shade700));
  }

  /// Hozircha real qurilma (RS232/kamera/server) ulanish holati kuzatilmagani
  /// uchun statik "ulangan" qaytaradi — struktura tayyor, real qiymat
  /// keyinchalik shu yerga ulanadi.
  bool _qurilmaUlanganmi() => true;

  MahsulotBoyichaHolat? _mahsulotHolati(String kod) {
    if (_smenaHolati == null) return null;
    for (final m in _smenaHolati!.mahsulotlar) {
      if (m.mahsulotKodi == kod) return m;
    }
    return null;
  }

  String _vaqtQisqa(DateTime v) {
    String ikki(int s) => s.toString().padLeft(2, '0');
    return '${ikki(v.hour)}:${ikki(v.minute)}:${ikki(v.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();
    final lok = holat.lok;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.scale),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Kip Tarozi — ${lok.t("smena")} ${holat.foydalanuvchi?.smena ?? ""}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_navbatUzunligi > 0) _navbatIndikatori(lok),
          _ulanishIkonkasi(Icons.dns_rounded, lok.t('server'), lok),
          _ulanishIkonkasi(Icons.videocam_rounded, lok.t('kamera'), lok),
          _ulanishIkonkasi(Icons.monitor_weight_rounded, lok.t('tarozi'), lok),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Center(child: SoatWidget())),
          IconButton(
            icon: Icon(holat.temaRejimi == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => holat.temaniAlmashtirish(),
          ),
          TextButton(
            onPressed: () => holat.tilniAlmashtirish(),
            child: Text(holat.til.name.toUpperCase(), style: const TextStyle(color: Colors.white)),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => holat.chiqish()),
          const SizedBox(width: 8),
        ],
      ),
      // Uch ustunli qat'iy tuzilish. O'rta ustundagi og'irlik qutisi QAT'IY
      // _panelBalandligi (270px). O'ng ustundagi surat paneli esa mustaqil va
      // kattaroq (Expanded) — lekin butun ekran baribir bitta ekranga sig'adi,
      // scroll yo'q (ichki panellar o'z joyiga moslashadi).
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 26, child: _chapPanel(lok)),
          const VerticalDivider(width: 1),
          Expanded(flex: 37, child: _ortaPanel(lok)),
          const VerticalDivider(width: 1),
          Expanded(flex: 37, child: _ongPanel(lok)),
        ],
      ),
    );
  }

  Widget _ulanishIkonkasi(IconData ikonka, String nomi, dynamic lok) {
    final ulanganmi = _qurilmaUlanganmi();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Tooltip(
        message: '$nomi: ${ulanganmi ? lok.t("ulangan") : lok.t("ulanmagan")}',
        child: Icon(ikonka, size: 28, color: ulanganmi ? Colors.greenAccent : Colors.redAccent.shade100),
      ),
    );
  }

  /// AppBar'dagi kichik indikator — lokal navbatda kutilayotgan (hali
  /// yuborilmagan) kiplar soni. Faqat son > 0 bo'lganda ko'rinadi.
  Widget _navbatIndikatori(dynamic lok) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: lok.t('navbat_tooltip'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.orange.shade800,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _navbatSinxronlanmoqda
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                '$_navbatUzunligi ${lok.t('navbat_indikator')}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =======================================================================
  // 1-USTUN (chap, ~26%): mahsulot tanlash, partiya ochish, progress, Excel
  // =======================================================================

  Widget _chapPanel(dynamic lok) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mahsulotGridi(lok),
          const SizedBox(height: 12),
          Expanded(
            child: _tanlanganMahsulot == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _partiyaRaqamiKontrolleri,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: lok.t('partiya_raqami'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _partiyaniOchish(),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 38,
                          child: ElevatedButton(
                            onPressed: _partiyaYuklanmoqda ? null : _partiyaniOchish,
                            child: _partiyaYuklanmoqda
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(lok.t('partiya_ochish')),
                          ),
                        ),
                        _songiPartiyalarQismi(lok),
                        if (_ochiqPartiyalar.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(lok.t('ochiq_partiyalar'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _ochiqPartiyalar
                                .map(
                                  (p) => _partiyaChipi(
                                    matn: '#${p.partiyaRaqami} (${p.kipSoni}/${_nishon(p.mahsulotKodi)})',
                                    faol: _tanlanganPartiya?.id == p.id,
                                    onTap: () => _partiyaniTanlash(p),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        if (_tanlanganPartiya != null) ...[
                          const SizedBox(height: 12),
                          _partiyaProgressPaneli(lok),
                        ],
                        const SizedBox(height: 12),
                        _mahsulotExcelTugmasi(lok),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () => smenaKalendarDialogniKorsat(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kipTaroziYashil),
                foregroundColor: kipTaroziYashil,
              ),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(lok.t('kalendar'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: _excelYuklanmoqda ? null : _excelYuklab,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kipTaroziYashil),
                foregroundColor: kipTaroziYashil,
              ),
              icon: _excelYuklanmoqda
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kipTaroziYashil),
                    )
                  : const Icon(Icons.download, size: 16),
              label: Text(lok.t('excel_yuklab_olish'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Tanlangan mahsulot bo'yicha tor Excel eksport tugmasi (bugungi kun,
  /// o'z smenasi, faqat shu mahsulot). Chap panelda mahsulot tanlanganda
  /// ko'rinadi.
  Widget _mahsulotExcelTugmasi(dynamic lok) {
    final mahsulot = _tanlanganMahsulot;
    return SizedBox(
      width: double.infinity,
      height: 38,
      child: OutlinedButton.icon(
        onPressed: _mahsulotExcelYuklanmoqda || mahsulot == null ? null : _mahsulotExcelYuklab,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kipTaroziYashil),
          foregroundColor: kipTaroziYashil,
        ),
        icon: _mahsulotExcelYuklanmoqda
            ? const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: kipTaroziYashil),
              )
            : const Icon(Icons.file_download_outlined, size: 16),
        label: Text(
          mahsulot == null
              ? lok.t('smena_mahsulot_excel')
              : '${lok.t('smena_mahsulot_excel')}: ${mahsulot.nomi}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// 2x2 mahsulot tugmalari — HAR BIRI QAT'IY 64px balandlikda (kenglikka
  /// bog'liq aspect-ratio emas), shuning uchun kattaroq shrift/padding
  /// ekran o'lchamidan qat'iy nazar bir xil ko'rinadi.
  Widget _mahsulotGridi(dynamic lok) {
    Widget katak(int i) {
      if (i >= _mahsulotlar.length) return const Expanded(child: SizedBox.shrink());
      return Expanded(child: _mahsulotTugmasi(_mahsulotlar[i]));
    }

    return Column(
      children: [
        SizedBox(height: 64, child: Row(children: [katak(0), const SizedBox(width: 8), katak(1)])),
        const SizedBox(height: 8),
        SizedBox(height: 64, child: Row(children: [katak(2), const SizedBox(width: 8), katak(3)])),
      ],
    );
  }

  Widget _mahsulotTugmasi(Mahsulot m) {
    final rang = mahsulotRangi(m.kod);
    final tanlanganmi = _tanlanganMahsulot?.id == m.id;
    return Material(
      color: tanlanganmi ? rang : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _mahsulotTanlash(m),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: rang, width: tanlanganmi ? 0 : 1.6),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            m.nomi,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: tanlanganmi ? Colors.white : rang,
            ),
          ),
        ),
      ),
    );
  }

  /// Faol/tanlangan holatda to'q yashil fon + oq matn, aks holda kulrang fon —
  /// "So'nggi ishlatilganlar" va "Ochiq partiyalar" chiplari shu bitta
  /// uslubdan foydalanadi.
  Widget _partiyaChipi({required String matn, required bool faol, required VoidCallback onTap}) {
    return ActionChip(
      label: Text(
        matn,
        style: TextStyle(color: faol ? Colors.white : Colors.black87, fontWeight: faol ? FontWeight.bold : FontWeight.normal),
      ),
      backgroundColor: faol ? kipTaroziYashil : Colors.grey.shade200,
      side: BorderSide(color: faol ? kipTaroziYashil : Colors.grey.shade300),
      onPressed: onTap,
    );
  }

  Widget _songiPartiyalarQismi(dynamic lok) {
    final royxat = _songiPartiyalar[_tanlanganMahsulot?.kod] ?? [];
    if (royxat.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lok.t('song_ishlatilganlar'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: royxat
                .map(
                  (raqam) => _partiyaChipi(
                    matn: '#$raqam',
                    faol: _tanlanganPartiya?.partiyaRaqami == raqam,
                    onTap: () => _songiPartiyaTanlandi(raqam),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  /// Yumshoq yashil gradient fonli progress-karta.
  Widget _partiyaProgressPaneli(dynamic lok) {
    final p = _tanlanganPartiya!;
    final nishon = _nishon(p.mahsulotKodi);
    final progress = (p.kipSoni / nishon).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF6F1), Color(0xFFF5FAF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kipTaroziYashil.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${lok.t("progress")}: #${p.partiyaRaqami} — ${p.kipSoni}/$nishon',
            style: const TextStyle(fontWeight: FontWeight.bold, color: kipTaroziYashil),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white,
              color: kipTaroziYashil,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${p.jamiKg.toStringAsFixed(1)} kg',
            style: TextStyle(color: kipTaroziYashil.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // =======================================================================
  // 2-USTUN (o'rta, ~37%): og'irlik qutisi, Saqlash, smena ko'rsatkichi
  // =======================================================================

  Widget _ortaPanel(dynamic lok) {
    final saqlashFaolmi = _tanlanganPartiya != null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: _panelBalandligi, width: double.infinity, child: _ogirlikQutisi(lok)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: saqlashFaolmi ? _saqlashTugmasiFaol(lok) : _saqlashTugmasiNofaol(lok),
          ),
          const SizedBox(height: 16),
          Text(
            lok.t('smena_korsatkichi_bugun'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Expanded(child: _smenaKartalariGridi(lok)),
        ],
      ),
    );
  }

  /// Saqlash bosilgandan keyingi 3 soniyalik oddiy kutish ham, tarmoq
  /// so'rovi davom etayotgan holat ham xuddi shu "band" ko'rinishni
  /// ishlatadi — faqat matn farq qiladi ("Kuting..." vs "Saqlash").
  Widget _saqlashTugmasiFaol(dynamic lok) {
    final bandmi = _saqlashYuklanmoqda || _saqlashVaqtinchaNofaol;
    return ElevatedButton.icon(
      onPressed: bandmi ? null : () => _saqlash(),
      icon: bandmi
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.save, size: 20),
      label: Text(
        bandmi ? lok.t('kuting') : lok.t('saqlash'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Partiya hali tanlanmaganda ko'rsatiladigan nofaol holat — kulrang
  /// gradient, bosib bo'lmaydi.
  Widget _saqlashTugmasiNofaol(dynamic lok) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.save, size: 20, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              lok.t('saqlash'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  /// Og'irlik ko'rsatkichi + rang-signal — QAT'IY 270px balandlikdagi quti
  /// (tashqarida SizedBox bilan beriladi). Ichidagi raqam qat'iy 48px —
  /// bundan katta bo'lmaydi, chunki qutining o'zi allaqachon katta va
  /// diqqatga sazovor, raqamni yanada kattalashtirish shart emas.
  ///
  /// Tarozi 0 kg bo'lsa QIZIL gradient/chegara ("Tarozi bo'sh"), yuk
  /// qo'yilib >0 bo'lsa YASHIL ("Barqaror") — bu holat Saqlash bosilgandan
  /// keyin ham (maydon tozalangan bo'lsa ham) yashil bo'lib qoladi, kip olib
  /// tashlanib qayta 0 ga tushgandagina yana qizilga qaytadi.
  Widget _ogirlikQutisi(dynamic lok) {
    final qizilmi = !_yukBor;
    final gradient = qizilmi
        ? const [Color(0xFFFDECEC), Color(0xFFFCE0E0)]
        : const [Color(0xFFEAF6F1), Color(0xFFD9EEE4)];
    const qizilChegara = Color(0xFFD64545);
    const qizilMatn = Color(0xFFB33A3A);
    final chegaraRangi = qizilmi ? qizilChegara : kipTaroziYashil;
    final matnRangi = qizilmi ? qizilMatn : kipTaroziYashil;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chegaraRangi, width: 2.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 10, color: matnRangi),
              const SizedBox(width: 8),
              Text(
                qizilmi ? lok.t('tarozi_bosh') : lok.t('barqaror'),
                style: TextStyle(color: matnRangi, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _ogirlikKontrolleri,
            focusNode: _ogirlikFokusi,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: matnRangi),
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: TextStyle(fontSize: 48, color: matnRangi.withValues(alpha: 0.35)),
              suffixText: ' kg',
              suffixStyle: TextStyle(fontSize: 18, color: matnRangi.withValues(alpha: 0.6)),
              border: InputBorder.none,
              isCollapsed: true,
            ),
            onSubmitted: (_) => _saqlashYuklanmoqda ? null : _saqlash(),
          ),
        ],
      ),
    );
  }

  /// 2x2 mahsulot kartochkalari — qolgan bo'sh joyni to'liq egallaydi
  /// (Expanded orqali berilgan joyga aniq moslashadi, aspect-ratio taxminiga
  /// tayanmaydi), har biri o'z brend rangida chegaralangan.
  Widget _smenaKartalariGridi(dynamic lok) {
    if (_mahsulotlar.isEmpty) return const SizedBox.shrink();

    Widget katak(int i) {
      if (i >= _mahsulotlar.length) return const Expanded(child: SizedBox.shrink());
      final m = _mahsulotlar[i];
      final h = _mahsulotHolati(m.kod);
      final rang = mahsulotRangi(m.kod);
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: rang.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: rang, width: 1.5),
          ),
          // FittedBox — juda past ekranlarda katak balandligi tor bo'lib
          // qolsa ham (masalan kichik notebook oynasi), matn hech qachon
          // RenderFlex overflow bermaydi, faqat mutanosib ravishda kichrayadi.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m.nomi,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: rang),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text('${h?.soni ?? 0}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: rang)),
                Text(
                  '${(h?.jamiKg ?? 0).toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: Row(children: [katak(0), katak(1)])),
        Expanded(child: Row(children: [katak(2), katak(3)])),
      ],
    );
  }

  // =======================================================================
  // 3-USTUN (o'ng, ~37%): so'nggi kip surati, smena tarixi
  // =======================================================================

  Widget _ongPanel(dynamic lok) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Surat paneli endi og'irlik qutisidan MUSTAQIL — mavjud bo'sh joyga
          // qarab imkon qadar katta (Expanded, kattaroq ulush). Ichki
          // LayoutBuilder surat o'lchamini har doim panel ichiga sig'diradi,
          // shuning uchun "bitta ekran, scroll yo'q" talabi buzilmaydi.
          Expanded(flex: 3, child: _suratPaneli(lok)),
          const SizedBox(height: 6),
          Text(
            lok.t('songgi_kip_surati'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Text(
            _tanlanganMahsulot == null
                ? lok.t('smena_tarixi')
                : '${lok.t("smena_tarixi")} — ${_tanlanganMahsulot!.nomi}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Expanded(flex: 2, child: _smenaTarixiPaneli(lok)),
        ],
      ),
    );
  }

  /// So'nggi kip surati paneli — chiziqli (dashed) chegara bilan. Tashqi quti
  /// endi Expanded (og'irlik qutisidan mustaqil, kattaroq). Ichidagi kvadrat
  /// surat mavjud joyning kichikroq o'lchamiga (kenglik/balandlik) moslashadi
  /// — hech qachon panel chegarasidan chiqmaydi.
  Widget _suratPaneli(dynamic lok) {
    final suratYoli = _oxirgiSaqlanganKip?['surat_yoli'] as String?;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xFFF2F7F5), borderRadius: BorderRadius.circular(16)),
        ),
        CustomPaint(painter: _ChiziqliChegaraRasmchisi(rang: Colors.grey.shade400)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Panel kattalashgani uchun yuqori chegara ham oshirildi — amalda
              // min(kenglik, balandlik) hukmron, ya'ni surat hech qachon
              // paneldan chiqmaydi.
              final andoza = math.min(constraints.maxWidth, constraints.maxHeight).clamp(0.0, 720.0);

              Widget ichki;
              if (_oxirgiSaqlanganKip == null) {
                ichki = _suratPlaceholder(Icons.photo_camera_outlined, lok.t('hali_kip_saqlanmagan'), andoza);
              } else if (suratYoli == null || suratYoli.isEmpty) {
                ichki = _suratPlaceholder(Icons.image_not_supported_outlined, lok.t('surat_yoq'), andoza);
              } else {
                ichki = ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    suratYoli,
                    key: ValueKey(suratYoli),
                    headers: suratSarlavhalari(_holat.api.token),
                    width: andoza,
                    height: andoza,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: andoza,
                        height: andoza,
                        color: Colors.grey.shade100,
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) =>
                        _suratPlaceholder(Icons.broken_image_outlined, lok.t('surat_yuklanmadi'), andoza),
                  ),
                );
              }

              return Center(child: SizedBox(width: andoza, height: andoza, child: ichki));
            },
          ),
        ),
      ],
    );
  }

  Widget _suratPlaceholder(IconData ikonka, String matn, double andoza) {
    return Container(
      width: andoza,
      height: andoza,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ikonka, color: Colors.grey.shade400, size: 36),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(matn, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Ichki scroll'ga ega smena-tarixi ro'yxati — joriy mahsulot bo'yicha
  /// bugun tortilgan kiplar, kip raqami+vaqt+rangli og'irlik bilan.
  Widget _smenaTarixiPaneli(dynamic lok) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: _smenaRoyxati.isEmpty
          ? Center(
              child: _smenaRoyxatiYuklanmoqda
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(lok.t('tarix_yoq'), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )
          : ListView.separated(
              itemCount: _smenaRoyxati.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, i) {
                final y = _smenaRoyxati[i];
                final bekorMi = y['holati'] != 'aktiv';
                final chiziq = bekorMi ? TextDecoration.lineThrough : null;
                final rangi = bekorMi ? Colors.grey.shade400 : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          '#${y['kip_raqami']}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, decoration: chiziq, color: rangi),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          _vaqtQisqa(DateTime.parse(y['vaqt'] as String).toLocal()),
                          style: TextStyle(fontSize: 11, color: rangi ?? Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${(y['ogirlik'] as num).toStringAsFixed(1)} kg',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: chiziq,
                            color: rangi ?? kipTaroziYashil,
                          ),
                        ),
                      ),
                      if (!bekorMi)
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade600),
                            tooltip: lok.t('kip_togrilash_dialog_sarlavha'),
                            onPressed: () => _kipTogrilashSorash(
                              kipId: y['id'] as int,
                              kipRaqami: y['kip_raqami'] as int,
                              ogirlik: (y['ogirlik'] as num).toDouble(),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _kipTogrilashSorash({required int kipId, required int kipRaqami, required double ogirlik}) async {
    final natija = await kipTogrilashDialogniKorsat(
      context: context,
      holat: _holat,
      mahsulotlar: _mahsulotlar,
      kipId: kipId,
      kipRaqami: kipRaqami,
      ogirlik: ogirlik,
    );
    if (natija == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_holat.lok.t('kip_togrilash_yuborildi'))));
    }
  }
}

/// Surat paneli uchun chiziqli (dashed) burchakli to'rtburchak chegara —
/// paket qo'shmasdan, oddiy CustomPainter bilan chiziladi.
class _ChiziqliChegaraRasmchisi extends CustomPainter {
  final Color rang;
  const _ChiziqliChegaraRasmchisi({required this.rang});

  static const _chiziqUzunligi = 6.0;
  static const _bosliqUzunligi = 5.0;
  static const _chegaraKengligi = 1.6;
  static const _burchakRadiusi = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = rang
      ..style = PaintingStyle.stroke
      ..strokeWidth = _chegaraKengligi;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _chegaraKengligi / 2,
        _chegaraKengligi / 2,
        size.width - _chegaraKengligi,
        size.height - _chegaraKengligi,
      ),
      const Radius.circular(_burchakRadiusi),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var masofa = 0.0;
      while (masofa < metric.length) {
        final keyingi = math.min(masofa + _chiziqUzunligi, metric.length);
        canvas.drawPath(metric.extractPath(masofa, keyingi), paint);
        masofa = keyingi + _bosliqUzunligi;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChiziqliChegaraRasmchisi oldDelegate) => oldDelegate.rang != rang;
}
