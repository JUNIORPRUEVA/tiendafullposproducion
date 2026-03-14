class TraceId {
  static int _seq = 0;

  static String next(String prefix) {
    _seq++;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$ts-$_seq';
  }
}
