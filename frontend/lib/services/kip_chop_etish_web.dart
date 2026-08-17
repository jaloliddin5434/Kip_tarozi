import 'package:web/web.dart' as web;

import '../i18n/strings.dart';
import '../models/kip_batafsil.dart';

const _konteynerId = 'kip-chop-korinishi';
const _uslubId = 'kip-chop-uslub';

String _holatiMatni(String holati, Lokalizatsiya lok) {
  switch (holati) {
    case 'aktiv':
      return lok.t('holati_aktiv');
    case 'bekor_qilingan':
      return lok.t('holati_bekor_qilingan');
    case 'tahrirlangan':
      return lok.t('holati_tahrirlangan');
    default:
      return holati;
  }
}

/// Butun ilovani emas, faqat shu bitta kipning ma'lumotlarini o'z ichiga
/// olgan chop etish ko'rinishini DOM'ga vaqtincha qo'shib, brauzerning
/// standart chop etish oynasini (`window.print()`) ochadi. Chrome'da
/// `print()` chaqiruvi foydalanuvchi dialogni yopguncha bloklaydi, shu
/// sabab qo'shilgan elementlar chaqiruvdan keyin darhol olib tashlanadi.
void kipniChopEtish(KipBatafsil kip, Lokalizatsiya lok) {
  web.document.getElementById(_konteynerId)?.remove();
  web.document.getElementById(_uslubId)?.remove();

  final uslub = web.document.createElement('style') as web.HTMLStyleElement
    ..id = _uslubId
    ..textContent = '''
      @media print {
        body > *:not(#$_konteynerId) { display: none !important; }
        #$_konteynerId { display: block !important; }
      }
      #$_konteynerId { display: none; }
    ''';
  web.document.head!.appendChild(uslub);

  final konteyner = web.document.createElement('div') as web.HTMLDivElement
    ..id = _konteynerId;
  konteyner.style
    ..fontFamily = 'sans-serif'
    ..padding = '32px'
    ..maxWidth = '480px';

  final sarlavha = web.document.createElement('h2') as web.HTMLHeadingElement
    ..textContent = 'Kip Tarozi';
  konteyner.appendChild(sarlavha);

  final kichikSarlavha = web.document.createElement('p') as web.HTMLParagraphElement
    ..textContent = lok.t('hujjat');
  kichikSarlavha.style
    ..color = '#666'
    ..marginTop = '0';
  konteyner.appendChild(kichikSarlavha);

  konteyner.appendChild(web.document.createElement('hr'));

  void qator(String belgi, String qiymat) {
    final satr = web.document.createElement('div') as web.HTMLDivElement;
    satr.style.margin = '6px 0';

    final belgiElementi = web.document.createElement('span') as web.HTMLSpanElement
      ..textContent = '$belgi: ';
    belgiElementi.style
      ..color = '#666'
      ..display = 'inline-block'
      ..width = '160px';

    final qiymatElementi = web.document.createElement('span') as web.HTMLSpanElement
      ..textContent = qiymat;
    qiymatElementi.style.fontWeight = 'bold';

    satr.appendChild(belgiElementi);
    satr.appendChild(qiymatElementi);
    konteyner.appendChild(satr);
  }

  qator(lok.t('mahsulot'), kip.mahsulotNomi);
  qator(lok.t('partiya'), '#${kip.partiyaRaqami}');
  qator(lok.t('kip_qisqa'), '${kip.kipRaqami}');
  qator(lok.t('ogirlik'), '${kip.ogirlik.toStringAsFixed(1)} ${lok.t("kg")}');
  qator(lok.t('smena'), kip.smena);
  qator(lok.t('operator'), kip.operatorIsm);
  qator(lok.t('vaqt'), kip.vaqt.toLocal().toString().substring(0, 16));
  qator(lok.t('holati'), _holatiMatni(kip.holati, lok));

  final idBelgisi = web.document.createElement('p') as web.HTMLParagraphElement
    ..textContent = 'ID: ${kip.id}';
  idBelgisi.style
    ..color = '#999'
    ..fontSize = '11px'
    ..marginTop = '24px';
  konteyner.appendChild(idBelgisi);

  web.document.body!.appendChild(konteyner);

  web.window.print();

  konteyner.remove();
  uslub.remove();
}
