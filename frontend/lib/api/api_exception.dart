class ApiException implements Exception {
  final int statusCode;
  final String xabar;
  final dynamic tafsilot;

  ApiException(this.statusCode, this.xabar, {this.tafsilot});

  @override
  String toString() => xabar;
}
