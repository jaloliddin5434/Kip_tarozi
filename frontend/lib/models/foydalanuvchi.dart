class Foydalanuvchi {
  final int id;
  final String ism;
  final String login;
  final String rol; // admin | operator | tayyor_mahsulotlar
  final String? smena;

  Foydalanuvchi({required this.id, required this.ism, required this.login, required this.rol, this.smena});

  factory Foydalanuvchi.fromJson(Map<String, dynamic> j) => Foydalanuvchi(
        id: j['id'],
        ism: j['ism'],
        login: j['login'],
        rol: j['rol'],
        smena: j['smena'],
      );
}
