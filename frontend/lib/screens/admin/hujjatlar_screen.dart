import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../models/hujjat.dart';
import '../../services/hujjat_pdf.dart';
import '../../state/app_state.dart';
import '../../widgets/kip_batafsil_dialog.dart';

class HujjatlarEkrani extends StatefulWidget {
  const HujjatlarEkrani({super.key});

  @override
  State<HujjatlarEkrani> createState() => _HujjatlarEkraniState();
}

class _HujjatlarEkraniState extends State<HujjatlarEkrani> {
  Sahifalangan<HujjatKip>? _sahifa;
  bool _yuklanmoqda = true;
  String? _xato;
  int _joriySahifa = 1;

  final _mahsulotKontrolleri = TextEditingController();
  final _kipRaqamiKontrolleri = TextEditingController();
  String? _smenaFiltri;

  @override
  void initState() {
    super.initState();
    _yuklash();
  }

  Future<void> _yuklash() async {
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final query = <String, dynamic>{'sahifa': _joriySahifa, 'sahifa_hajmi': 30};
      if (_mahsulotKontrolleri.text.trim().isNotEmpty) query['mahsulot_kodi'] = _mahsulotKontrolleri.text.trim();
      if (_kipRaqamiKontrolleri.text.trim().isNotEmpty) query['kip_raqami'] = int.tryParse(_kipRaqamiKontrolleri.text.trim());
      if (_smenaFiltri != null) query['smena'] = _smenaFiltri;

      final javob = await context.read<AppState>().api.get('/hujjatlar/kiplar', query: query);
      setState(() => _sahifa = Sahifalangan.fromJson(javob, (e) => HujjatKip.fromJson(e)));
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _chopEtish(HujjatKip kip, dynamic lok) async {
    final hujjat = kipHujjatiQur(kip, lok);
    await Printing.layoutPdf(onLayout: (format) async => hujjat.save());
  }

  void _filtrniTozalash() {
    _mahsulotKontrolleri.clear();
    _kipRaqamiKontrolleri.clear();
    _smenaFiltri = null;
    _joriySahifa = 1;
    _yuklash();
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _mahsulotKontrolleri,
                  decoration: InputDecoration(labelText: lok.t('mahsulot'), border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _kipRaqamiKontrolleri,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: lok.t('kip_qisqa'), border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: _smenaFiltri,
                  decoration: InputDecoration(labelText: lok.t('smena'), border: const OutlineInputBorder(), isDense: true),
                  items: ['A', 'B', 'C', 'D'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _smenaFiltri = v),
                ),
              ),
              ElevatedButton(onPressed: () { _joriySahifa = 1; _yuklash(); }, child: Text(lok.t('filtr'))),
              OutlinedButton(onPressed: _filtrniTozalash, child: Text(lok.t('tozalash'))),
            ],
          ),
          const SizedBox(height: 16),
          if (_yuklanmoqda) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _sahifa != null) Expanded(child: _jadval(lok)),
        ],
      ),
    );
  }

  Widget _jadval(dynamic lok) {
    final sahifa = _sahifa!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: Text(lok.t('sana'))),
                  DataColumn(label: Text(lok.t('mahsulot'))),
                  DataColumn(label: Text(lok.t('partiya'))),
                  DataColumn(label: Text(lok.t('kip_qisqa'))),
                  DataColumn(label: Text(lok.t('kg'))),
                  DataColumn(label: Text(lok.t('smena'))),
                  DataColumn(label: Text(lok.t('operator'))),
                  DataColumn(label: Text(lok.t('holati'))),
                  DataColumn(label: Text(lok.t('chop_etish'))),
                ],
                rows: sahifa.items
                    .map(
                      (k) => DataRow(
                        onSelectChanged: (_) => kipBatafsilDialogniKorsat(context: context, kipId: k.id),
                        cells: [
                          DataCell(Text('${k.vaqt.toLocal()}'.substring(0, 16))),
                          DataCell(Text(k.mahsulotNomi)),
                          DataCell(Text('#${k.partiyaRaqami}')),
                          DataCell(Text('${k.kipRaqami}')),
                          DataCell(Text(k.ogirlik.toStringAsFixed(1))),
                          DataCell(Text(k.smena)),
                          DataCell(Text(k.operatorIsm)),
                          DataCell(
                            Text(k.holati, style: TextStyle(color: k.holati == 'aktiv' ? Colors.green : Colors.orange)),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.print, size: 20),
                              tooltip: lok.t('chop_etish'),
                              onPressed: () => _chopEtish(k, lok),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _joriySahifa > 1 ? () { setState(() => _joriySahifa--); _yuklash(); } : null,
            ),
            Text('${sahifa.sahifa} / ${(sahifa.jami / sahifa.sahifaHajmi).ceil().clamp(1, 999999)}  (${lok.t("jami")}: ${sahifa.jami})'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: sahifa.sahifa * sahifa.sahifaHajmi < sahifa.jami ? () { setState(() => _joriySahifa++); _yuklash(); } : null,
            ),
          ],
        ),
      ],
    );
  }
}
