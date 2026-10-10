import 'package:intl/intl.dart';

class DateFormatter {
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final DateFormat _timeOnlyFormat = DateFormat('HH:mm:ss');
  static final DateFormat _dateOnlyFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _compactTimeFormat = DateFormat('HH:mm:ss.S');

  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormat.format(dateTime.toLocal());
  }

  static String formatTime(DateTime dateTime) {
    return _timeOnlyFormat.format(dateTime.toLocal());
  }

  static String formatDate(DateTime dateTime) {
    return _dateOnlyFormat.format(dateTime.toLocal());
  }

  static String formatCompactTime(DateTime dateTime) {
    return _compactTimeFormat.format(dateTime.toLocal());
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
