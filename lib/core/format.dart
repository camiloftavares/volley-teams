const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// e.g. `Tue 22 Sep, 19:00`, in the device's local time.
String formatGameTime(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}, '
      '${two(local.hour)}:${two(local.minute)}';
}

/// e.g. `22 Sep 2026`.
String formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

String weekdayName(int weekday) => _weekdays[weekday - 1];
