import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final String name;
  final DateTime startedAt;
  final Stopwatch stopwatch = Stopwatch();

  _RunningActivity({
    required this.id,
    required this.name,
    required this.startedAt,
  }) {
    stopwatch.start();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _storageKey = 'completed_activities_jalali_v1';
  static const _tabTitles = ['ثبت زمان', 'فعالیت‌ها', 'گزارش‌گیری', 'تایمر معکوس'];
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
  Timer? _clock;
  final List<_RunningActivity> _runningActivities = [];
  List<_SavedActivity> _savedActivities = [];

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadActivities();
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final activity in _runningActivities) {
      activity.stopwatch.stop();
    }
    super.dispose();
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

  Future<void> _addActivity() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فعالیت جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'نام فعالیت',
            hintText: 'مثلاً مطالعه، ورزش یا کار',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('شروع فعالیت'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _runningActivities.insert(
        0,
        _RunningActivity(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          startedAt: DateTime.now(),
        ),
      );
    });
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
      name: activity.name,
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
          _buildPlaceholder(
            Icons.bar_chart_rounded,
            'گزارش‌گیری',
            'بخش گزارش‌گیری در مرحله بعدی تکمیل می‌شود.',
          ),
          _buildPlaceholder(
            Icons.hourglass_bottom_rounded,
            'تایمر معکوس',
            'بخش تایمر معکوس در مرحله بعدی تکمیل می‌شود.',
          ),
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
        ],
      ),
    );
  }

  Widget _buildTimeEntryPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
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
              const Text(
                'ساعت فعلی',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'فعالیت‌های در حال ثبت',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              _persianDigits(_runningActivities.length.toString()),
              style: TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_runningActivities.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8EAF0)),
            ),
            child: const Column(
              children: [
                Icon(Icons.timer_outlined, size: 34, color: Colors.black38),
                SizedBox(height: 8),
                Text(
                  'هنوز فعالیتی شروع نشده است',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          )
        else
          ..._runningActivities.map(_buildRunningActivityCard),
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _addActivity,
            style: FilledButton.styleFrom(
              backgroundColor: _accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'افزودن فعالیت',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRunningActivityCard(_RunningActivity activity) {
    final isRunning = activity.stopwatch.isRunning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  activity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _durationText(activity.stopwatch.elapsed),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? null : () => _startActivity(activity),
                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                  label: const Text('شروع'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isRunning ? () => _pauseActivity(activity) : null,
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('مکث'),
                  style: FilledButton.styleFrom(
                    foregroundColor: _accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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

  Widget _buildActivitiesPage() {
    if (_savedActivities.isEmpty) {
      return _buildPlaceholder(
        Icons.checklist_rounded,
        'فعالیت‌های ثبت‌شده',
        'فعالیت‌هایی که متوقف و ذخیره می‌کنی، در این قسمت نمایش داده می‌شوند.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'فعالیت‌های ذخیره‌شده (${_persianDigits(_savedActivities.length.toString())})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._savedActivities.map(
          (activity) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8EAF0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _detailLine('شروع', '${activity.startDate} - ${activity.startTime}'),
                const SizedBox(height: 6),
                _detailLine('پایان', '${activity.endDate} - ${activity.endTime}'),
                const Divider(height: 20),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 19),
                    const SizedBox(width: 7),
                    const Text('مدت فعالیت'),
                    const Spacer(),
                    Text(
                      _durationText(Duration(seconds: activity.durationSeconds)),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: _accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
