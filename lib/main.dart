import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  const initSettings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
  await _notifications.initialize(initSettings);
  runApp(const TimerApp());
}

class TimerApp extends StatelessWidget {
  const TimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'زمان‌شمار',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF356AE6)),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFFF7F8FC),
          elevation: 0,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const MainScreen(),
    );
  }
}

class _SavedActivity {
  final String name;
  final String startDate;
  final String startTime;
  final String endDate;
  final String endTime;
  final int durationSeconds;

  const _SavedActivity({
    required this.name,
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'startDate': startDate,
        'startTime': startTime,
        'endDate': endDate,
        'endTime': endTime,
        'durationSeconds': durationSeconds,
      };

  factory _SavedActivity.fromJson(Map<String, dynamic> json) {
    return _SavedActivity(
      name: json['name'] as String? ?? 'فعالیت بدون نام',
      startDate: json['startDate'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
    );
  }
}

class _RunningActivity {
  final String id;
  String name;
  final DateTime startedAt;
  final Stopwatch stopwatch = Stopwatch();
  final TextEditingController nameController = TextEditingController();

  _RunningActivity({
    required this.id,
    required this.name,
    required this.startedAt,
  }) {
    nameController.text = name;
    stopwatch.start();
  }

  void dispose() {
    stopwatch.stop();
    nameController.dispose();
  }
}

class _CountdownTimer {
  final int id; final String title; final int totalSeconds;
  int remainingSeconds; DateTime? endsAt; bool running=false; bool finished=false;
  _CountdownTimer({required this.id, required this.title, required this.totalSeconds}) : remainingSeconds=totalSeconds;
}


class _ChecklistItem {
  String title;
  bool done;
  _ChecklistItem({required this.title, this.done = false});
  Map<String, dynamic> toJson() => {'title': title, 'done': done};
  factory _ChecklistItem.fromJson(Map<String, dynamic> json) => _ChecklistItem(
    title: json['title'] as String? ?? '',
    done: json['done'] as bool? ?? false,
  );
}

class _Checklist {
  final String id;
  String title;
  final List<_ChecklistItem> items;
  _Checklist({required this.id, required this.title, List<_ChecklistItem>? items})
      : items = items ?? [];
  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'items': items.map((e) => e.toJson()).toList(),
  };
  factory _Checklist.fromJson(Map<String, dynamic> json) => _Checklist(
    id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
    title: json['title'] as String? ?? 'چک‌لیست',
    items: (json['items'] as List<dynamic>? ?? [])
      .map((e) => _ChecklistItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
  );
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _storageKey = 'completed_activities_jalali_v1';
  static const _namesStorageKey = 'activity_names_v1';
  static const _checklistsStorageKey = 'checklists_v1';
  static const _tabTitles = ['ثبت زمان', 'فعالیت‌ها', 'گزارش‌گیری', 'تایمر معکوس', 'چک‌لیست‌ها'];
  static const _colors = [
    Color(0xFF356AE6),
    Color(0xFF00897B),
    Color(0xFF8E44AD),
    Color(0xFFE07828),
    Color(0xFFCE496B),
    Color(0xFF34495E),
  ];

  int _selectedIndex = 0;
  Color _accentColor = _colors.first;
  DateTime _now = DateTime.now();
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;
  final Set<String> _reportSelectedNames = {};
  final List<_CountdownTimer> _countdowns=[];
  Timer? _countdownTicker;
  int _wheelHours=0, _wheelMinutes=5, _wheelSeconds=0, _nextCountdownId=1000;
  Timer? _clock;
  final List<_RunningActivity> _runningActivities = [];
  List<_SavedActivity> _savedActivities = [];
  List<String> _activityNames = [];
  List<_Checklist> _checklists = [];

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _initializeData();
    _loadChecklists();
    _initializeAlarmNotifications();
    _countdownTicker=Timer.periodic(const Duration(seconds:1), (_) => _tickCountdowns());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _countdownTicker?.cancel();
    for (final activity in _runningActivities) {
      activity.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _loadActivities();
    await _loadActivityNames();
  }

  Future<void> _loadActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _savedActivities = decoded
            .map((item) => _SavedActivity.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate));
      });
    } catch (_) {
      // Ignore an invalid local cache rather than preventing the app from opening.
    }
  }

  Future<void> _loadActivityNames() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_namesStorageKey) ?? [];
    final names = <String>{...stored, ..._savedActivities.map((item) => item.name)};
    if (!mounted) return;
    setState(() => _activityNames = names.toList()..sort());
    if (names.length != stored.length) await prefs.setStringList(_namesStorageKey, _activityNames);
  }

  Future<void> _persistActivityNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_namesStorageKey, _activityNames);
  }

  Future<void> _addActivityToCatalog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('افزودن فعالیت جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'نام فعالیت',
            hintText: 'مثلاً مطالعه یا ورزش',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('ذخیره فعالیت'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (_activityNames.any((item) => item.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این فعالیت قبلاً اضافه شده است')),
      );
      return;
    }
    setState(() {
      _activityNames.add(name);
      _activityNames.sort();
    });
    await _persistActivityNames();
  }

  void _startNewActivity(String name) {
    if (name.trim().isEmpty) return;
    final activity = _RunningActivity(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      startedAt: DateTime.now(),
    );
    setState(() => _runningActivities.insert(0, activity));
  }

  void _createActivityTimer() {
    final activity = _RunningActivity(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '',
      startedAt: DateTime.now(),
    );
    setState(() => _runningActivities.insert(0, activity));
  }

  Future<void> _saveActivityName(_RunningActivity activity) async {
    final name = activity.nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا نام فعالیت را وارد کن.')),
      );
      return;
    }
    activity.name = name;
    if (!_activityNames.any((item) => item.toLowerCase() == name.toLowerCase())) {
      setState(() {
        _activityNames.add(name);
        _activityNames.sort();
      });
      await _persistActivityNames();
    } else if (mounted) {
      setState(() {});
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('نام «$name» ذخیره شد؛ تایمر همچنان فعال است.')),
    );
  }

  Future<void> _persistActivities() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_savedActivities.map((item) => item.toJson()).toList()),
    );
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _persianDigits(String value) {
    const english = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < english.length; i++) {
      value = value.replaceAll(english[i], persian[i]);
    }
    return value;
  }

  String _jalaliDate(DateTime date) {
    final jalali = Jalali.fromDateTime(date);
    return _persianDigits(
      '${jalali.year}/${_twoDigits(jalali.month)}/${_twoDigits(jalali.day)}',
    );
  }

  String _clockTime(DateTime date, {bool withSeconds = true}) {
    final value = withSeconds
        ? '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}:${_twoDigits(date.second)}'
        : '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
    return _persianDigits(value);
  }

  String _durationText(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return _persianDigits(
      '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}',
    );
  }

  void _startActivity(_RunningActivity activity) {
    if (activity.stopwatch.isRunning) return;
    setState(() => activity.stopwatch.start());
  }

  void _pauseActivity(_RunningActivity activity) {
    if (!activity.stopwatch.isRunning) return;
    setState(() => activity.stopwatch.stop());
  }

  Future<void> _stopActivity(_RunningActivity activity) async {
    activity.stopwatch.stop();
    final endedAt = DateTime.now();
    final saved = _SavedActivity(
      name: activity.name.trim().isEmpty ? 'فعالیت بدون نام' : activity.name.trim(),
      startDate: _jalaliDate(activity.startedAt),
      startTime: _clockTime(activity.startedAt),
      endDate: _jalaliDate(endedAt),
      endTime: _clockTime(endedAt),
      durationSeconds: activity.stopwatch.elapsed.inSeconds,
    );

    setState(() {
      _runningActivities.removeWhere((item) => item.id == activity.id);
      _savedActivities.insert(0, saved);
    });
    activity.dispose();
    await _persistActivities();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('فعالیت «${activity.name}» ذخیره شد')),
    );
  }

  Future<void> _showColorSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'رنگ عناصر صفحه ثبت زمان',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _colors.map((color) {
                final selected = color == _accentColor;
                return InkWell(
                  onTap: () {
                    setState(() => _accentColor = color);
                    Navigator.pop(sheetContext);
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.black87, width: 3)
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tabTitles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              tooltip: 'تنظیم رنگ‌ها',
              onPressed: _showColorSettings,
              icon: const Icon(Icons.palette_outlined),
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildTimeEntryPage(),
          _buildActivitiesPage(),
          _buildReportsPage(),
          _buildCountdownPage(),
          _buildChecklistsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'ثبت زمان',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist_rounded),
            label: 'فعالیت‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'گزارش‌گیری',
          ),
          NavigationDestination(
            icon: Icon(Icons.hourglass_bottom_rounded),
            selectedIcon: Icon(Icons.hourglass_full_rounded),
            label: 'تایمر معکوس',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'چک‌لیست‌ها',
          ),
        ],
      ),
    );
  }

  Widget _buildTimeEntryPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            color: _accentColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.20),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                _persianDigits(_jalaliDate(_now)),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                _clockTime(_now),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 5),
              const Text('ساعت فعلی', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 18),
              if (_runningActivities.isNotEmpty) ...[
                const Divider(color: Colors.white30, height: 1),
                const SizedBox(height: 14),
                ..._runningActivities.map(_buildRunningActivityCard),
                const SizedBox(height: 4),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _createActivityTimer,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('فعالیت جدید'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRunningActivityCard(_RunningActivity activity) {
    final isRunning = activity.stopwatch.isRunning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _durationText(activity.stopwatch.elapsed),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                isRunning ? 'در حال اجرا' : 'مکث شده',
                style: TextStyle(
                  color: isRunning ? Colors.green.shade700 : Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: activity.nameController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'نام فعالیت',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => activity.name = value,
                  onSubmitted: (_) => _saveActivityName(activity),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'ذخیره نام فعالیت',
                onPressed: () => _saveActivityName(activity),
                icon: const Icon(Icons.save_outlined),
                style: IconButton.styleFrom(backgroundColor: _accentColor, foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? null : () => _startActivity(activity),
                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                  label: const Text('شروع'),
                  style: OutlinedButton.styleFrom(foregroundColor: _accentColor, padding: const EdgeInsets.symmetric(vertical: 9)),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isRunning ? () => _pauseActivity(activity) : null,
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('مکث'),
                  style: FilledButton.styleFrom(foregroundColor: _accentColor, padding: const EdgeInsets.symmetric(vertical: 9)),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _stopActivity(activity),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('توقف'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFE8E8),
                    foregroundColor: const Color(0xFFC62828),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime? _reportDate(_SavedActivity item) {
    try {
      int n(String s) {
        const fa = '۰۱۲۳۴۵۶۷۸۹';
        const ar = '٠١٢٣٤٥٦٧٨٩';
        for (var i = 0; i < 10; i++) {
          s = s.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
        }
        return int.parse(s.replaceAll(RegExp(r'[^0-9]'), ''));
      }
      final d = item.startDate.split('/');
      final t = item.startTime.split(':');
      return Jalali(n(d[0]), n(d[1]), n(d[2])).toDateTime().add(Duration(hours: n(t[0]), minutes: n(t[1]), seconds: t.length > 2 ? n(t[2]) : 0));
    } catch (_) { return null; }
  }

  List<_SavedActivity> _reportRows() => _savedActivities.where((a) {
    if (_reportSelectedNames.isNotEmpty && !_reportSelectedNames.contains(a.name)) return false;
    final d = _reportDate(a);
    if (d == null) return false;
    if (_reportStartDate != null && d.isBefore(DateTime(_reportStartDate!.year, _reportStartDate!.month, _reportStartDate!.day))) return false;
    if (_reportEndDate != null && d.isAfter(DateTime(_reportEndDate!.year, _reportEndDate!.month, _reportEndDate!.day, 23, 59, 59))) return false;
    return true;
  }).toList();

  Future<void> _pickReportDate(bool start) async {
    final d = await showDatePicker(context: context, initialDate: (start ? _reportStartDate : _reportEndDate) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() { if (start) { _reportStartDate = d; } else { _reportEndDate = d; } });
  }

  Future<void> _exportExcel() async {
    final rows = _reportRows();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای این فیلترها گزارشی وجود ندارد.')));
      return;
    }
    final book = Excel.createExcel();
    final detail = book['جزئیات نوبت‌ها'];
    detail.appendRow([TextCellValue('فعالیت'), TextCellValue('تاریخ شروع'), TextCellValue('ساعت شروع'), TextCellValue('تاریخ پایان'), TextCellValue('ساعت پایان'), TextCellValue('مدت (ثانیه)'), TextCellValue('مدت نوبت')]);
    for (final a in rows) {
      detail.appendRow([TextCellValue(a.name), TextCellValue(a.startDate), TextCellValue(a.startTime), TextCellValue(a.endDate), TextCellValue(a.endTime), IntCellValue(a.durationSeconds), TextCellValue(_durationText(Duration(seconds: a.durationSeconds)))]);
    }
    final byDay = <String, int>{};
    final byName = <String, int>{};
    for (final a in rows) {
      final k = a.name + '|' + a.startDate;
      byDay[k] = (byDay[k] ?? 0) + a.durationSeconds;
      byName[a.name] = (byName[a.name] ?? 0) + a.durationSeconds;
    }
    final daily = book['جمع روزانه'];
    daily.appendRow([TextCellValue('فعالیت'), TextCellValue('تاریخ'), TextCellValue('مجموع روز (ثانیه)'), TextCellValue('مجموع روز')]);
    for (final e in byDay.entries) {
      final p = e.key.split('|');
      daily.appendRow([TextCellValue(p[0]), TextCellValue(p[1]), IntCellValue(e.value), TextCellValue(_durationText(Duration(seconds: e.value)))]);
    }
    final total = book['جمع کل'];
    total.appendRow([TextCellValue('فعالیت'), TextCellValue('تعداد نوبت'), TextCellValue('مجموع کل (ثانیه)'), TextCellValue('مجموع کل')]);
    for (final e in byName.entries) {
      total.appendRow([TextCellValue(e.key), IntCellValue(rows.where((a) => a.name == e.key).length), IntCellValue(e.value), TextCellValue(_durationText(Duration(seconds: e.value)))]);
    }
    final bytes = book.encode();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(dir.path + '/time_report_' + DateTime.now().millisecondsSinceEpoch.toString() + '.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'گزارش زمان فعالیت‌ها');
  }

  Widget _buildReportsPage() {
    final rows = _reportRows();
    final seconds = rows.fold<int>(0, (s, a) => s + a.durationSeconds);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('فیلتر گزارش', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _pickReportDate(true),
            child: Text('از: ' + (_reportStartDate == null ? 'همه' : _jalaliDate(_reportStartDate!))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _pickReportDate(false),
            child: Text('تا: ' + (_reportEndDate == null ? 'همه' : _jalaliDate(_reportEndDate!))),
          ),
        ),
      ]),
      TextButton(onPressed: () => setState(() { _reportStartDate = null; _reportEndDate = null; _reportSelectedNames.clear(); }), child: const Text('پاک کردن فیلترها')),
      const Text('فعالیت‌ها (بدون انتخاب، همه فعالیت‌ها):'),
      Wrap(spacing: 8, children: _activityNames.map((n) => FilterChip(label: Text(n), selected: _reportSelectedNames.contains(n), onSelected: (v) => setState(() { if (v) { _reportSelectedNames.add(n); } else { _reportSelectedNames.remove(n); } }))).toList()),
      const SizedBox(height: 12),
      Text('تعداد نوبت: ' + _persianDigits(rows.length.toString()) + ' | مجموع: ' + _durationText(Duration(seconds: seconds))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _exportExcel, icon: const Icon(Icons.file_download), label: const Text('خروجی اکسل (.xlsx)')),
      const SizedBox(height: 24),
      const Text('پشتیبان‌گیری و بازیابی', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const Text('فهرست فعالیت‌ها و سوابق ثبت‌شده در فایل پشتیبان ذخیره می‌شوند.'),
      OutlinedButton.icon(onPressed: _backupData, icon: const Icon(Icons.backup), label: const Text('تهیه فایل پشتیبان')),
      OutlinedButton.icon(onPressed: _restoreData, icon: const Icon(Icons.settings_backup_restore), label: const Text('بازیابی از فایل پشتیبان')),
    ]);
  }

  Future<void> _backupData() async {
    final content = const JsonEncoder.withIndent('  ').convert({
      'format': 'timer_main_backup',
      'version': 1,
      'activityNames': _activityNames,
      'savedActivities': _savedActivities.map((a) => a.toJson()).toList(),
      'checklists': _checklists.map((a) => a.toJson()).toList(),
    });
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'ذخیره فایل پشتیبان',
      fileName: 'timer_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(content),
    );
    if (path != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل پشتیبان ذخیره شد.')));
  }

  Future<void> _restoreData() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (picked == null || picked.files.single.bytes == null || !mounted) return;
    try {
      final data = jsonDecode(utf8.decode(picked.files.single.bytes!)) as Map<String, dynamic>;
      if (data['format'] != 'timer_main_backup' || data['version'] != 1) throw const FormatException('فایل پشتیبان معتبر نیست.');
      final names = (data['activityNames'] as List<dynamic>).cast<String>().toSet().toList();
      final saved = (data['savedActivities'] as List<dynamic>).map((e) => _SavedActivity.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final restoredChecklists = (data['checklists'] as List<dynamic>? ?? []).map((e) => _Checklist.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('بازیابی اطلاعات'),
        content: const Text('اطلاعات فعلی با فایل پشتیبان جایگزین می‌شود. ادامه می‌دهی؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بازیابی'))],
      ));
      if (yes != true || !mounted) return;
      setState(() { _activityNames = names..sort(); _savedActivities = saved; _checklists = restoredChecklists; _runningActivities.clear(); });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_namesStorageKey, _activityNames);
      await prefs.setString(_storageKey, jsonEncode(_savedActivities.map((a) => a.toJson()).toList()));
      await prefs.setString(_checklistsStorageKey, jsonEncode(_checklists.map((a) => a.toJson()).toList()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بازیابی انجام شد.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در بازیابی: ' + e.toString())));
    }
  }



  Future<void> _loadChecklists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_checklistsStorageKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() => _checklists = data.map((e) =>
        _Checklist.fromJson(Map<String, dynamic>.from(e as Map))).toList());
    } catch (_) {
      // Ignore invalid local checklist data.
    }
  }

  Future<void> _persistChecklists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checklistsStorageKey,
      jsonEncode(_checklists.map((e) => e.toJson()).toList()));
  }

  Future<String?> _askChecklistText({required String title, String hint = '', String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ذخیره')),
      ],
    ));
    controller.dispose();
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> _addChecklist() async {
    final name = await _askChecklistText(title: 'چک‌لیست جدید', hint: 'مثلاً برنامه روزانه');
    if (name == null || !mounted) return;
    setState(() => _checklists.insert(0, _Checklist(
      id: DateTime.now().microsecondsSinceEpoch.toString(), title: name)));
    await _persistChecklists();
  }

  Future<void> _addChecklistItem(_Checklist list) async {
    final text = await _askChecklistText(title: 'افزودن مورد', hint: 'عنوان مورد چک‌لیست');
    if (text == null || !mounted) return;
    setState(() => list.items.add(_ChecklistItem(title: text)));
    await _persistChecklists();
  }

  Future<void> _editChecklist(_Checklist list) async {
    final name = await _askChecklistText(title: 'ویرایش نام چک‌لیست', initial: list.title);
    if (name == null || !mounted) return;
    setState(() => list.title = name);
    await _persistChecklists();
  }

  Future<void> _editChecklistItem(_Checklist list, _ChecklistItem item) async {
    final title = await _askChecklistText(title: 'ویرایش مورد', initial: item.title);
    if (title == null || !mounted) return;
    setState(() => item.title = title);
    await _persistChecklists();
  }

  Future<bool> _confirmChecklistDelete(String title) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف'),
      content: Text('«$title» حذف شود؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
      ],
    )) ?? false;
  }

  Future<void> _deleteChecklist(_Checklist list) async {
    if (!await _confirmChecklistDelete(list.title) || !mounted) return;
    setState(() => _checklists.remove(list));
    await _persistChecklists();
  }

  Future<void> _deleteChecklistItem(_Checklist list, _ChecklistItem item) async {
    if (!await _confirmChecklistDelete(item.title) || !mounted) return;
    setState(() => list.items.remove(item));
    await _persistChecklists();
  }

  Widget _buildChecklistsPage() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Expanded(child: Text('چک‌لیست‌های من', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
        FilledButton.icon(onPressed: _addChecklist, icon: const Icon(Icons.add), label: const Text('چک‌لیست جدید'),
          style: FilledButton.styleFrom(backgroundColor: _accentColor)),
      ]),
      const SizedBox(height: 8),
      const Text('برای هر بخش از کارها یک چک‌لیست جدا بساز و موارد انجام‌شده را علامت بزن.',
        style: TextStyle(color: Colors.black54, height: 1.6)),
      const SizedBox(height: 14),
      if (_checklists.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(child: Text('هنوز چک‌لیستی نساخته‌ای.')))
      else
        ..._checklists.map((list) {
          final done = list.items.where((e) => e.done).length;
          final total = list.items.length;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            child: ExpansionTile(
              key: PageStorageKey<String>(list.id),
              leading: Icon(Icons.checklist_rounded, color: _accentColor),
              title: Text(list.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('انجام‌شده: ${_persianDigits(done.toString())} از ${_persianDigits(total.toString())}'),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _editChecklist(list);
                  if (value == 'delete') _deleteChecklist(list);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('ویرایش نام')),
                  PopupMenuItem(value: 'delete', child: Text('حذف چک‌لیست')),
                ],
              ),
              children: [
                if (total > 0)
                  Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(value: total == 0 ? 0 : done / total,
                      color: _accentColor, backgroundColor: const Color(0xFFE9ECF3))),
                if (list.items.isEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Text('هنوز موردی اضافه نشده است.')),
                ...list.items.map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(value: item.done, activeColor: _accentColor,
                    onChanged: (value) async {
                      setState(() => item.done = value ?? false);
                      await _persistChecklists();
                    }),
                  title: Text(item.title,
                    style: TextStyle(decoration: item.done ? TextDecoration.lineThrough : null,
                      color: item.done ? Colors.black45 : null)),
                  onTap: () async {
                    setState(() => item.done = !item.done);
                    await _persistChecklists();
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _editChecklistItem(list, item);
                      if (value == 'delete') _deleteChecklistItem(list, item);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                )),
                Align(alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: () => _addChecklistItem(list),
                    icon: const Icon(Icons.add), label: const Text('افزودن مورد'))),
              ],
            ),
          );
        }),
    ]);
  }

  Future<void> _initializeAlarmNotifications() async {
    final android=_notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    const channel=AndroidNotificationChannel('countdown_alarm_channel','هشدار پایان تایمر',
      description:'هشدار صوتی هنگام پایان تایمر معکوس',importance:Importance.max,playSound:true,enableVibration:true);
    await android?.createNotificationChannel(channel);
  }
  NotificationDetails get _alarmDetails => const NotificationDetails(android:AndroidNotificationDetails(
    'countdown_alarm_channel','هشدار پایان تایمر',channelDescription:'هشدار صوتی هنگام پایان تایمر معکوس',
    importance:Importance.max,priority:Priority.max,playSound:true,enableVibration:true,
    category:AndroidNotificationCategory.alarm,audioAttributesUsage:AudioAttributesUsage.alarm));
  Future<void> _scheduleCountdownAlarm(_CountdownTimer item) async {
    if(item.endsAt==null)return;
    await _notifications.zonedSchedule(item.id,'زمان تایمر به پایان رسید',item.title,
      tz.TZDateTime.from(item.endsAt!,tz.local),_alarmDetails,
      androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,payload:'countdown:'+item.id.toString());
  }
  void _tickCountdowns(){
    var changed=false;
    for(final item in _countdowns){
      if(!item.running||item.endsAt==null)continue;
      final left=item.endsAt!.difference(DateTime.now()).inSeconds;
      final next=left<=0?0:left;
      if(next!=item.remainingSeconds){item.remainingSeconds=next;changed=true;}
      if(next<=0){item.running=false;item.finished=true;item.endsAt=null;_finishCountdown(item);changed=true;}
    }
    if(changed&&mounted)setState((){});
  }
  Future<void> _finishCountdown(_CountdownTimer item) async {
    await _notifications.cancel(item.id);
    await _notifications.show(item.id,'پایان تایمر','زمان «'+item.title+'» به پایان رسید.',_alarmDetails,payload:'countdown:'+item.id.toString());
    SystemSound.play(SystemSoundType.alert);
  }
  void _addCountdown(){
    final seconds=_wheelHours*3600+_wheelMinutes*60+_wheelSeconds;
    if(seconds<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابتدا یک زمان بیشتر از صفر انتخاب کن.')));return;}
    setState(()=>_countdowns.add(_CountdownTimer(id:_nextCountdownId++,title:'تایمر '+(_countdowns.length+1).toString(),totalSeconds:seconds)));
  }
  Future<void> _startCountdown(_CountdownTimer item) async {
    if(item.running||item.remainingSeconds<=0)return;
    setState(() { item.running=true; item.finished=false; item.endsAt=DateTime.now().add(Duration(seconds:item.remainingSeconds)); });
    await _scheduleCountdownAlarm(item);
  }
  Future<void> _pauseCountdown(_CountdownTimer item) async {
    if(!item.running)return;
    final remaining=item.endsAt!.difference(DateTime.now()).inSeconds;
    await _notifications.cancel(item.id);
    setState(() { item.remainingSeconds=remaining<0?0:remaining; item.running=false; item.endsAt=null; });
  }
  Future<void> _stopCountdown(_CountdownTimer item) async {
    await _notifications.cancel(item.id);
    setState(() { item.running=false; item.finished=false; item.endsAt=null; item.remainingSeconds=item.totalSeconds; });
  }
  String _countdownText(int seconds){
    final h=seconds~/3600,m=(seconds%3600)~/60,s=seconds%60;
    return _persianDigits(_twoDigits(h)+':'+_twoDigits(m)+':'+_twoDigits(s));
  }
  Widget _wheelPicker(String label, int max, int selected, ValueChanged<int> onChanged) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SizedBox(
            height: 154,
            child: ListWheelScrollView.useDelegate(
              itemExtent: 42,
              perspective: 0.003,
              diameterRatio: 1.5,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              controller: FixedExtentScrollController(initialItem: selected),
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: max + 1,
                builder: (context, index) => Center(
                  child: Text(
                    _persianDigits(_twoDigits(index)),
                    style: TextStyle(
                      fontSize: index == selected ? 25 : 18,
                      fontWeight: index == selected ? FontWeight.bold : FontWeight.normal,
                      color: index == selected ? _accentColor : Colors.black45,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownPage(){
    final selectedSeconds=_wheelHours*3600+_wheelMinutes*60+_wheelSeconds;
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('تنظیم تایمر جدید',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),const Text('ساعت، دقیقه و ثانیه را با حرکت دادن چرخ‌ها انتخاب کن.'),
      const SizedBox(height:12),
      Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20)),
        child:Column(children:[
          Row(children:[
            _wheelPicker('ساعت',99,_wheelHours,(v)=>setState(()=>_wheelHours=v)),
            _wheelPicker('دقیقه',59,_wheelMinutes,(v)=>setState(()=>_wheelMinutes=v)),
            _wheelPicker('ثانیه',59,_wheelSeconds,(v)=>setState(()=>_wheelSeconds=v)),
          ]),
          Text(_countdownText(selectedSeconds),style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:_accentColor)),
          const SizedBox(height:12),
          SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_addCountdown,icon:const Icon(Icons.add_alarm),
            label:const Text('افزودن تایمر'),style:FilledButton.styleFrom(backgroundColor:_accentColor))),
        ])),
      const SizedBox(height:22),
      Row(children:[const Expanded(child:Text('تایمرهای من',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold))),
        Text(_persianDigits(_countdowns.length.toString()),style:TextStyle(color:_accentColor,fontWeight:FontWeight.bold))]),
      const SizedBox(height:10),
      if(_countdowns.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('هنوز تایمری اضافه نشده است.')))
      else ..._countdowns.map(_buildCountdownCard),
    ]);
  }
  Widget _buildCountdownCard(_CountdownTimer item){
    final progress=item.totalSeconds==0?0.0:(item.remainingSeconds/item.totalSeconds).clamp(0.0,1.0);
    return Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(14),
      decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE8EAF0))),
      child:Column(children:[
        Row(children:[Expanded(child:Text(item.title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),
          IconButton(tooltip:'حذف تایمر',onPressed:()async{await _notifications.cancel(item.id);if(mounted)setState(()=>_countdowns.remove(item));},
            icon:const Icon(Icons.delete_outline,color:Colors.redAccent))]),
        const SizedBox(height:8),
        SizedBox(width:174,height:174,child:Stack(alignment:Alignment.center,children:[
          SizedBox.expand(child:CircularProgressIndicator(value:progress,strokeWidth:11,strokeCap:StrokeCap.round,
            backgroundColor:const Color(0xFFE9ECF3),valueColor:AlwaysStoppedAnimation<Color>(_accentColor))),
          Column(mainAxisSize:MainAxisSize.min,children:[
            Text(_countdownText(item.remainingSeconds),textDirection:TextDirection.ltr,
              style:const TextStyle(fontSize:25,fontWeight:FontWeight.bold,fontFeatures:[FontFeature.tabularFigures()])),
            const SizedBox(height:4),Text(item.finished?'پایان یافته':item.running?'در حال شمارش':'متوقف',style:const TextStyle(color:Colors.black54,fontSize:12)),
          ]),
        ])),
        const SizedBox(height:12),
        Row(children:[
          Expanded(child:FilledButton.icon(onPressed:item.running||item.remainingSeconds==0?null:()=>_startCountdown(item),icon:const Icon(Icons.play_arrow),label:const Text('شروع'))),
          const SizedBox(width:8),
          Expanded(child:OutlinedButton.icon(onPressed:item.running?()=>_pauseCountdown(item):null,icon:const Icon(Icons.pause),label:const Text('مکث'))),
          const SizedBox(width:8),
          Expanded(child:OutlinedButton.icon(onPressed:()=>_stopCountdown(item),icon:const Icon(Icons.stop),label:const Text('توقف'))),
        ]),
      ]));
  }

  Widget _buildActivitiesPage() {
    final totalByName = <String, int>{};
    for (final item in _savedActivities) {
      totalByName[item.name] = (totalByName[item.name] ?? 0) + item.durationSeconds;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(child: Text('فهرست فعالیت‌ها', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
            FilledButton.icon(
              onPressed: _addActivityToCatalog,
              icon: const Icon(Icons.add, size: 19),
              label: const Text('فعالیت جدید'),
              style: FilledButton.styleFrom(backgroundColor: _accentColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'فعالیت‌هایی که اینجا می‌سازی، در بخش ثبت زمان با تایپ نامشان قابل انتخاب هستند.',
          style: TextStyle(color: Colors.black54, height: 1.6),
        ),
        const SizedBox(height: 14),
        if (_activityNames.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('هنوز فعالیتی اضافه نکرده‌ای.')),
          )
        else
          ..._activityNames.map((name) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EAF0)),
            ),
            child: Row(
              children: [
                Icon(Icons.label_outline_rounded, color: _accentColor),
                const SizedBox(width: 10),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(
                  _durationText(Duration(seconds: totalByName[name] ?? 0)),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )),
      ],
    );
  }

  Widget _detailLine(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.start,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(IconData icon, String title, String description) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 54, color: _accentColor),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                height: 1.8,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
