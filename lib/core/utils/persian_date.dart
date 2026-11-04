class PersianDate implements Comparable<PersianDate> {
  const PersianDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const monthNames = <String>[
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  factory PersianDate.fromDateTime(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    var gregorianYear = date.year - 1600;
    final gregorianMonth = date.month - 1;
    final gregorianDay = date.day - 1;

    var dayNumber =
        365 * gregorianYear +
        ((gregorianYear + 3) ~/ 4) -
        ((gregorianYear + 99) ~/ 100) +
        ((gregorianYear + 399) ~/ 400);
    const gregorianMonthDays = <int>[
      31,
      28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];
    for (var index = 0; index < gregorianMonth; index++) {
      dayNumber += gregorianMonthDays[index];
    }
    if (gregorianMonth > 1 &&
        (gregorianYear % 4 == 0 && gregorianYear % 100 != 0 ||
            gregorianYear % 400 == 0)) {
      dayNumber++;
    }
    dayNumber += gregorianDay;

    var jalaliDayNumber = dayNumber - 79;
    final cycles = jalaliDayNumber ~/ 12053;
    jalaliDayNumber %= 12053;
    var jalaliYear = 979 + 33 * cycles + 4 * (jalaliDayNumber ~/ 1461);
    jalaliDayNumber %= 1461;
    if (jalaliDayNumber >= 366) {
      jalaliYear += (jalaliDayNumber - 1) ~/ 365;
      jalaliDayNumber = (jalaliDayNumber - 1) % 365;
    }
    final jalaliMonth = jalaliDayNumber < 186
        ? 1 + jalaliDayNumber ~/ 31
        : 7 + (jalaliDayNumber - 186) ~/ 30;
    final jalaliDay = jalaliDayNumber < 186
        ? 1 + jalaliDayNumber % 31
        : 1 + (jalaliDayNumber - 186) % 30;
    return PersianDate(jalaliYear, jalaliMonth, jalaliDay);
  }

  DateTime toDateTime() {
    var jalaliYear = year - 979;
    final jalaliMonth = month - 1;
    final jalaliDay = day - 1;

    var dayNumber =
        365 * jalaliYear +
        (jalaliYear ~/ 33) * 8 +
        ((jalaliYear % 33 + 3) ~/ 4);
    for (var index = 0; index < jalaliMonth; index++) {
      dayNumber += index < 6 ? 31 : 30;
    }
    dayNumber += jalaliDay + 79;

    var gregorianYear = 1600 + 400 * (dayNumber ~/ 146097);
    dayNumber %= 146097;
    var leap = true;
    if (dayNumber >= 36525) {
      dayNumber--;
      gregorianYear += 100 * (dayNumber ~/ 36524);
      dayNumber %= 36524;
      if (dayNumber >= 365) {
        dayNumber++;
      } else {
        leap = false;
      }
    }
    gregorianYear += 4 * (dayNumber ~/ 1461);
    dayNumber %= 1461;
    if (dayNumber >= 366) {
      leap = false;
      dayNumber--;
      gregorianYear += dayNumber ~/ 365;
      dayNumber %= 365;
    }

    final monthDays = <int>[
      31,
      leap ? 29 : 28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];
    var gregorianMonth = 0;
    while (gregorianMonth < monthDays.length &&
        dayNumber >= monthDays[gregorianMonth]) {
      dayNumber -= monthDays[gregorianMonth];
      gregorianMonth++;
    }
    return DateTime(gregorianYear, gregorianMonth + 1, dayNumber + 1);
  }

  int get daysInMonth {
    if (month <= 6) return 31;
    if (month <= 11) return 30;
    final thirtieth = PersianDate(year, 12, 30);
    return PersianDate.fromDateTime(thirtieth.toDateTime()) == thirtieth
        ? 30
        : 29;
  }

  PersianDate addMonths(int months) {
    final absoluteMonth = year * 12 + month - 1 + months;
    final nextYear = absoluteMonth ~/ 12;
    final nextMonth = absoluteMonth % 12 + 1;
    return PersianDate(nextYear, nextMonth, 1);
  }

  @override
  int compareTo(PersianDate other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) return byYear;
    final byMonth = month.compareTo(other.month);
    if (byMonth != 0) return byMonth;
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is PersianDate &&
        year == other.year &&
        month == other.month &&
        day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String toPersianDigits(Object value) {
  const western = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var result = value.toString();
  for (var index = 0; index < western.length; index++) {
    result = result.replaceAll(western[index], persian[index]);
  }
  return result;
}

String formatPersianDate(DateTime value, {bool includeYear = true}) {
  final date = PersianDate.fromDateTime(value);
  final day = toPersianDigits(date.day);
  final month = PersianDate.monthNames[date.month - 1];
  return includeYear
      ? '$day $month ${toPersianDigits(date.year)}'
      : '$day $month';
}

String formatPersianDateRange(DateTime start, DateTime end) {
  final first = PersianDate.fromDateTime(start);
  final last = PersianDate.fromDateTime(end);
  if (first == last) return formatPersianDate(start);
  if (first.year == last.year && first.month == last.month) {
    return '${toPersianDigits(first.day)} تا ${toPersianDigits(last.day)} '
        '${PersianDate.monthNames[first.month - 1]} ${toPersianDigits(first.year)}';
  }
  if (first.year == last.year) {
    return '${toPersianDigits(first.day)} ${PersianDate.monthNames[first.month - 1]} تا '
        '${toPersianDigits(last.day)} ${PersianDate.monthNames[last.month - 1]} '
        '${toPersianDigits(first.year)}';
  }
  return '${formatPersianDate(start)} تا ${formatPersianDate(end)}';
}
