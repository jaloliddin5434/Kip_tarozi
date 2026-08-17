class Mahsulot {
  final int id;
  final String kod;
  final String nomi;

  Mahsulot({required this.id, required this.kod, required this.nomi});

  factory Mahsulot.fromJson(Map<String, dynamic> j) => Mahsulot(id: j['id'], kod: j['kod'], nomi: j['nomi']);
}
