bool parseBoolAppSetting(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  return t == '1' || t == 'true' || t == 'yes';
}
