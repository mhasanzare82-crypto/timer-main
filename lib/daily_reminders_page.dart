import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:timezone/timezone.dart' as tz;

class _Reminder {
  final int id;
  final String text;
  final String repeat;
  final String date;
  final int hour;
  final int minute;
  final List<int> days;
  final bool enabled;
  final String? soundPath;

  const _Reminder({
    required this.id,
    required this.text,
    required this.repeat,
    required this.date,
    required this.hour,
    required this.minute,
    required this.days,
    required this.enabled,
    this.soundPath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'repeat': repeat,
    'date': date,
    'hour': hour,
    'minute': minute,
    'days': days,
    'enabled': enabled,
    'soundPath': soundPath,
  };

  factory _Reminder.fromJson(Map<String, dynamic> json) => _Reminder(
    id: json['id'] as int,
    text: json['text'] as String? ?? '',
    repeat: json['repeat'] as String? ?? 'once',
    date: json['date'] as String? ?? '',
    hour: json['hour'] as int? ?? 8,
    minute: json['minute'] as int? ?? 0,
    days: (json['days'] as List? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
    enabled: json['enabled'] as bool? ?? true,
    soundPath: json['soundPath'] as String?,
  );

  _Reminder copyWith({bool? enabled}) => _Reminder(
    id: id,
    text: text,
    repeat: repeat,
    date: date,
    hour: hour,
    minute: minute,
    days: days,
    enabled: enabled ?? this.enabled,
    soundPath: soundPath,
  );
}

class DailyRemindersPage extends StatefulWidget {
  const DailyRemindersPage({super.key});

  @override
  State<DailyRemindersPage> createState() => _DailyRemindersPageState();
}

class _DailyRemindersPageState extends State<DailyRemindersPage> {
  static const _storageKey = 'daily_reminders_v1';
  static const _timezoneChannel = MethodChannel('timer_main/device_timezone');
  static const _soundChannel = MethodChannel('timer_main/reminder_sounds');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final List<_Reminder> _items = [];

  bool _loading = true;
  bool _notificationsReady = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final zoneName =
          await _timezoneChannel.invokeMethod<String>('getLocalTimezone');
      if (zoneName != null && zoneName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(zoneName));
      }
      _notificationsReady = true;
    } catch (error) {
      debugPrint('Reminder initialization failed: $error');
    }

    final preferences = await SharedPreferences.getInstance();
    try {
      final raw = preferences.getString(_storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _items.addAll(
          decoded.map(
            (item) => _Reminder.fromJson(Map<String, dynamic>.from(item as Map)),
          ),
        );
      }
    } catch (error) {
      debugPrint('Reminder storage could not be read: $error');
    }

    final now = DateTime.now();
    var changed = false;
    for (var index = 0; index < _items.length; index++) {
      final reminder = _items[index];
      if (reminder.enabled && reminder.repeat == 'once') {
        final date = _onceDate(reminder);
        if (date == null ||
            !DateTime(date.year, date.month, date.day, reminder.hour,
                    reminder.minute)
                .isAfter(now)) {
          _items[index] = reminder.copyWith(enabled: false);
          changed = true;
        }
      }
    }
    if (changed) await _save();

    if (mounted) setState(() => _loading = false);
    if (_notificationsReady) {
      for (final reminder in _items.where((item) => item.enabled)) {
        await _schedule(reminder);
      }
    }
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }

  int _notificationId(_Reminder reminder, int suffix) =>
      850000 + reminder.id * 10 + suffix;

  String _channelId(_Reminder reminder) {
    final soundName = reminder.soundPath == null
        ? 'default'
        : reminder.soundPath!.split('/').last.replaceAll(
              RegExp(r'[^a-zA-Z0-9_]'),
              '_',
            );
    return 'daily_reminder_${reminder.id}_$soundName';
  }

  Future<void> _createSoundChannel(_Reminder reminder) async {
    await _soundChannel.invokeMethod<void>('createReminderChannel', {
      'channelId': _channelId(reminder),
      'name': 'یادآوری ${reminder.id}',
      'soundFileName':
          reminder.soundPath == null
              ? null
              : reminder.soundPath!.split('/').last,
    });
  }

  Future<void> _deleteSoundChannel(String channelId) async {
    try {
      await _soundChannel.invokeMethod<void>(
        'deleteReminderChannel',
        {'channelId': channelId},
      );
    } catch (error) {
      debugPrint('Could not delete reminder sound channel: $error');
    }
  }

  Future<void> _cancelNotifications(_Reminder reminder) async {
    for (var suffix = 0; suffix <= 7; suffix++) {
      await _notifications.cancel(_notificationId(reminder, suffix));
    }
  }

  NotificationDetails _notificationDetails(_Reminder reminder) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId(reminder),
          'یادآوری ${reminder.id}',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.reminder,
        ),
      );

  DateTime? _onceDate(_Reminder reminder) {
    final parts = reminder.date.split('/');
    if (parts.length != 3) return null;
    try {
      return Jalali(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      ).toDateTime();
    } catch (_) {
      return null;
    }
  }

  DateTime _nextTime(int hour, int minute, [int? weekday]) {
    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    while (!candidate.isAfter(now) ||
        (weekday != null && candidate.weekday != weekday)) {
      candidate = candidate.add(const Duration(days: 1));
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day,
        hour,
        minute,
      );
    }
    return candidate;
  }

  Future<void> _schedule(_Reminder reminder) async {
    try {
      await _cancelNotifications(reminder);
      if (!_notificationsReady || !reminder.enabled) return;

      await _createSoundChannel(reminder);

      Future<void> addNotification(
        int suffix,
        DateTime date,
        DateTimeComponents? repeatComponent,
      ) async {
        await _notifications.zonedSchedule(
          _notificationId(reminder, suffix),
          'یادآوری روزانه',
          reminder.text,
          tz.TZDateTime.from(date, tz.local),
          _notificationDetails(reminder),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: repeatComponent,
          payload: 'daily-reminder:${reminder.id}',
        );
      }

      if (reminder.repeat == 'once') {
        final date = _onceDate(reminder);
        if (date == null) return;
        final scheduled = DateTime(
          date.year,
          date.month,
          date.day,
          reminder.hour,
          reminder.minute,
        );
        if (scheduled.isAfter(DateTime.now())) {
          await addNotification(0, scheduled, null);
        }
      } else if (reminder.repeat == 'daily') {
        await addNotification(
          0,
          _nextTime(reminder.hour, reminder.minute),
          DateTimeComponents.time,
        );
      } else {
        for (final weekday in reminder.days) {
          await addNotification(
            weekday,
            _nextTime(reminder.hour, reminder.minute, weekday),
            DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
    } catch (error) {
      debugPrint('Could not schedule reminder ${reminder.id}: $error');
      if (mounted) setState(() => _notificationsReady = false);
    }
  }

  Future<String?> _pickReminderSound(int reminderId) async {
    try {
      // file_picker 12+ exposes static APIs and returns a PlatformFile directly.
      final selected = await FilePicker.pickFile(type: FileType.audio);
      if (selected == null) return null;

      final audioBytes = await selected.readAsBytes();
      if (audioBytes.isEmpty) {
        throw StateError('The selected audio file is empty or unreadable.');
      }

      final supportDirectory = await getApplicationSupportDirectory();
      final soundDirectory =
          Directory('${supportDirectory.path}/reminder_sounds');
      await soundDirectory.create(recursive: true);

      final sourceName = selected.name;
      final dot = sourceName.lastIndexOf('.');
      final extension = dot >= 0 ? sourceName.substring(dot) : '.audio';
      final safeExtension =
          RegExp(r'^\.[a-zA-Z0-9]{1,8}$').hasMatch(extension)
              ? extension
              : '.audio';

      final random = math.Random.secure();
      final token = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final fileName = 'reminder_${reminderId}_${token}${safeExtension}';
      final destination = '${soundDirectory.path}/${fileName}';
      await File(destination).writeAsBytes(audioBytes, flush: true);
      return destination;
    } catch (error) {
      debugPrint('Could not select reminder sound: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('انتخاب یا ذخیره فایل صوتی انجام نشد.')),
        );
      }
      return null;
    }
  }

  Future<void> _removeTemporarySound(String? path, String? originalPath) async {
    if (path == null || path == originalPath) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _edit([_Reminder? old]) async {
    final textController = TextEditingController(text: old?.text ?? '');
    final draftId =
        old?.id ?? (DateTime.now().microsecondsSinceEpoch % 10000000);
    var soundPath = old?.soundPath;

    final today = Jalali.fromDateTime(DateTime.now());
    var date = old?.date ??
        '${today.year}/${today.month.toString().padLeft(2, '0')}/${today.day.toString().padLeft(2, '0')}';
    var repeat = old?.repeat ?? 'once';
    var hour = old?.hour ?? TimeOfDay.now().hour;
    var minute = old?.minute ?? TimeOfDay.now().minute;
    final weekdays = <int>{...(old?.days ?? const <int>[])};

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text(old == null ? 'یادآوری جدید' : 'ویرایش یادآوری'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: textController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'متن یادآوری',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await _pickReminderSound(draftId);
                          if (selected != null) {
                            final previous = soundPath;
                            refresh(() => soundPath = selected);
                            await _removeTemporarySound(
                              previous,
                              old?.soundPath,
                            );
                          }
                        },
                        icon: const Icon(Icons.music_note),
                        label: Text(
                          soundPath == null
                              ? 'انتخاب زنگ اختصاصی'
                              : soundPath!.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (soundPath != null)
                      IconButton(
                        tooltip: 'استفاده از زنگ پیش‌فرض',
                        onPressed: () async {
                          final previous = soundPath;
                          refresh(() => soundPath = null);
                          await _removeTemporarySound(
                            previous,
                            old?.soundPath,
                          );
                        },
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: repeat,
                  decoration: const InputDecoration(labelText: 'تکرار'),
                  items: const [
                    DropdownMenuItem(value: 'once', child: Text('یک‌بار')),
                    DropdownMenuItem(value: 'daily', child: Text('هر روز')),
                    DropdownMenuItem(value: 'weekly', child: Text('روزهای هفته')),
                  ],
                  onChanged: (value) =>
                      refresh(() => repeat = value ?? repeat),
                ),
                if (repeat == 'once')
                  TextFormField(
                    initialValue: date,
                    decoration: const InputDecoration(
                      labelText: 'تاریخ شمسی (سال/ماه/روز)',
                    ),
                    onChanged: (value) => date = value,
                  ),
                if (repeat == 'weekly') ...[
                  const SizedBox(height: 8),
                  const Text('روزهای هفته را انتخاب کن'),
                  Wrap(
                    spacing: 4,
                    children: List.generate(
                      7,
                      (index) => FilterChip(
                        label: Text(
                          const [
                            'دوشنبه',
                            'سه‌شنبه',
                            'چهارشنبه',
                            'پنجشنبه',
                            'جمعه',
                            'شنبه',
                            'یکشنبه',
                          ][index],
                        ),
                        selected: weekdays.contains(index + 1),
                        onSelected: (selected) => refresh(() {
                          if (selected) {
                            weekdays.add(index + 1);
                          } else {
                            weekdays.remove(index + 1);
                          }
                        }),
                      ),
                    ),
                  ),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: Text(
                    'ساعت ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final selected = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay(hour: hour, minute: minute),
                    );
                    if (selected != null) {
                      refresh(() {
                        hour = selected.hour;
                        minute = selected.minute;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final validText = textController.text.trim().isNotEmpty;
                final validDays = repeat != 'weekly' || weekdays.isNotEmpty;
                if (validText && validDays) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    final reminderText = textController.text.trim();
    textController.dispose();
    if (result != true || !mounted) {
      await _removeTemporarySound(soundPath, old?.soundPath);
      return;
    }

    if (repeat == 'once') {
      final parsed = _onceDate(
        _Reminder(
          id: draftId,
          text: '',
          repeat: 'once',
          date: date,
          hour: hour,
          minute: minute,
          days: const [],
          enabled: true,
        ),
      );
      if (parsed == null ||
          !DateTime(parsed.year, parsed.month, parsed.day, hour, minute)
              .isAfter(DateTime.now())) {
        await _removeTemporarySound(soundPath, old?.soundPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تاریخ و ساعت باید در آینده باشد و تاریخ شمسی معتبر وارد شود.',
              ),
            ),
          );
        }
        return;
      }
    }

    final reminder = _Reminder(
      id: draftId,
      text: reminderText,
      repeat: repeat,
      date: date,
      hour: hour,
      minute: minute,
      days: weekdays.toList()..sort(),
      enabled: old?.enabled ?? true,
      soundPath: soundPath,
    );

    final oldChannelId = old == null ? null : _channelId(old);
    final oldSoundPath = old?.soundPath;
    final index = _items.indexWhere((item) => item.id == draftId);
    setState(() {
      if (index < 0) {
        _items.add(reminder);
      } else {
        _items[index] = reminder;
      }
    });
    await _save();
    await _schedule(reminder);

    if (oldChannelId != null && oldChannelId != _channelId(reminder)) {
      await _deleteSoundChannel(oldChannelId);
    }
    if (oldSoundPath != null && oldSoundPath != soundPath) {
      await _removeTemporarySound(oldSoundPath, soundPath);
    }
  }

  Future<void> _toggle(_Reminder reminder, bool enabled) async {
    final index = _items.indexOf(reminder);
    if (index < 0) return;
    final updated = reminder.copyWith(enabled: enabled);
    setState(() => _items[index] = updated);
    await _save();
    await _schedule(updated);
  }

  Future<void> _delete(_Reminder reminder) async {
    await _cancelNotifications(reminder);
    await _deleteSoundChannel(_channelId(reminder));
    if (reminder.soundPath != null) {
      try {
        await File(reminder.soundPath!).delete();
      } catch (_) {}
    }
    setState(() => _items.remove(reminder));
    await _save();
  }

  String _repeatLabel(_Reminder reminder) {
    if (reminder.repeat == 'daily') return 'هر روز';
    if (reminder.repeat == 'weekly') {
      const names = [
        '',
        'دوشنبه',
        'سه‌شنبه',
        'چهارشنبه',
        'پنجشنبه',
        'جمعه',
        'شنبه',
        'یکشنبه',
      ];
      return reminder.days.map((day) => names[day]).join('، ');
    }
    return 'یک‌بار • ${reminder.date}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_alert),
      label: const Text('یادآوری جدید'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
            ? const Center(
                child: Text('هنوز یادآوری‌ای ثبت نکرده‌ای.'),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  if (!_notificationsReady)
                    const Text(
                      'راه‌اندازی اعلان‌ها کامل نشد؛ تنظیمات اعلان گوشی را بررسی کن.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ..._items.map(
                    (reminder) => Card(
                      child: ListTile(
                        isThreeLine: true,
                        title: Text(
                          reminder.text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${reminder.hour.toString().padLeft(2, '0')}:${reminder.minute.toString().padLeft(2, '0')} • ${_repeatLabel(reminder)}${reminder.soundPath == null ? '' : ' • زنگ اختصاصی'}',
                        ),
                        leading: Switch(
                          value: reminder.enabled,
                          onChanged: (value) => _toggle(reminder, value),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) => value == 'edit'
                              ? _edit(reminder)
                              : _delete(reminder),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('ویرایش'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
  );
}
).hasMatch(extension)
              ? extension
              : '.audio';

      final random = math.Random.secure();
      final token = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final fileName = 'reminder_${reminderId}_${token}${safeExtension}';
      final destination = '${soundDirectory.path}/${fileName}';
      await File(destination).writeAsBytes(audioBytes, flush: true);
      return destination;
    } catch (error) {
      debugPrint('Could not select reminder sound: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('انتخاب یا ذخیره فایل صوتی انجام نشد.')),
        );
      }
      return null;
    }
  }

  Future<void> _removeTemporarySound(String? path, String? originalPath) async {
    if (path == null || path == originalPath) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _edit([_Reminder? old]) async {
    final textController = TextEditingController(text: old?.text ?? '');
    final draftId =
        old?.id ?? (DateTime.now().microsecondsSinceEpoch % 10000000);
    var soundPath = old?.soundPath;

    final today = Jalali.fromDateTime(DateTime.now());
    var date = old?.date ??
        '${today.year}/${today.month.toString().padLeft(2, '0')}/${today.day.toString().padLeft(2, '0')}';
    var repeat = old?.repeat ?? 'once';
    var hour = old?.hour ?? TimeOfDay.now().hour;
    var minute = old?.minute ?? TimeOfDay.now().minute;
    final weekdays = <int>{...(old?.days ?? const <int>[])};

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text(old == null ? 'یادآوری جدید' : 'ویرایش یادآوری'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: textController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'متن یادآوری',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await _pickReminderSound(draftId);
                          if (selected != null) {
                            final previous = soundPath;
                            refresh(() => soundPath = selected);
                            await _removeTemporarySound(
                              previous,
                              old?.soundPath,
                            );
                          }
                        },
                        icon: const Icon(Icons.music_note),
                        label: Text(
                          soundPath == null
                              ? 'انتخاب زنگ اختصاصی'
                              : soundPath!.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (soundPath != null)
                      IconButton(
                        tooltip: 'استفاده از زنگ پیش‌فرض',
                        onPressed: () async {
                          final previous = soundPath;
                          refresh(() => soundPath = null);
                          await _removeTemporarySound(
                            previous,
                            old?.soundPath,
                          );
                        },
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: repeat,
                  decoration: const InputDecoration(labelText: 'تکرار'),
                  items: const [
                    DropdownMenuItem(value: 'once', child: Text('یک‌بار')),
                    DropdownMenuItem(value: 'daily', child: Text('هر روز')),
                    DropdownMenuItem(value: 'weekly', child: Text('روزهای هفته')),
                  ],
                  onChanged: (value) =>
                      refresh(() => repeat = value ?? repeat),
                ),
                if (repeat == 'once')
                  TextFormField(
                    initialValue: date,
                    decoration: const InputDecoration(
                      labelText: 'تاریخ شمسی (سال/ماه/روز)',
                    ),
                    onChanged: (value) => date = value,
                  ),
                if (repeat == 'weekly') ...[
                  const SizedBox(height: 8),
                  const Text('روزهای هفته را انتخاب کن'),
                  Wrap(
                    spacing: 4,
                    children: List.generate(
                      7,
                      (index) => FilterChip(
                        label: Text(
                          const [
                            'دوشنبه',
                            'سه‌شنبه',
                            'چهارشنبه',
                            'پنجشنبه',
                            'جمعه',
                            'شنبه',
                            'یکشنبه',
                          ][index],
                        ),
                        selected: weekdays.contains(index + 1),
                        onSelected: (selected) => refresh(() {
                          if (selected) {
                            weekdays.add(index + 1);
                          } else {
                            weekdays.remove(index + 1);
                          }
                        }),
                      ),
                    ),
                  ),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: Text(
                    'ساعت ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final selected = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay(hour: hour, minute: minute),
                    );
                    if (selected != null) {
                      refresh(() {
                        hour = selected.hour;
                        minute = selected.minute;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final validText = textController.text.trim().isNotEmpty;
                final validDays = repeat != 'weekly' || weekdays.isNotEmpty;
                if (validText && validDays) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    final reminderText = textController.text.trim();
    textController.dispose();
    if (result != true || !mounted) {
      await _removeTemporarySound(soundPath, old?.soundPath);
      return;
    }

    if (repeat == 'once') {
      final parsed = _onceDate(
        _Reminder(
          id: draftId,
          text: '',
          repeat: 'once',
          date: date,
          hour: hour,
          minute: minute,
          days: const [],
          enabled: true,
        ),
      );
      if (parsed == null ||
          !DateTime(parsed.year, parsed.month, parsed.day, hour, minute)
              .isAfter(DateTime.now())) {
        await _removeTemporarySound(soundPath, old?.soundPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تاریخ و ساعت باید در آینده باشد و تاریخ شمسی معتبر وارد شود.',
              ),
            ),
          );
        }
        return;
      }
    }

    final reminder = _Reminder(
      id: draftId,
      text: reminderText,
      repeat: repeat,
      date: date,
      hour: hour,
      minute: minute,
      days: weekdays.toList()..sort(),
      enabled: old?.enabled ?? true,
      soundPath: soundPath,
    );

    final oldChannelId = old == null ? null : _channelId(old);
    final oldSoundPath = old?.soundPath;
    final index = _items.indexWhere((item) => item.id == draftId);
    setState(() {
      if (index < 0) {
        _items.add(reminder);
      } else {
        _items[index] = reminder;
      }
    });
    await _save();
    await _schedule(reminder);

    if (oldChannelId != null && oldChannelId != _channelId(reminder)) {
      await _deleteSoundChannel(oldChannelId);
    }
    if (oldSoundPath != null && oldSoundPath != soundPath) {
      await _removeTemporarySound(oldSoundPath, soundPath);
    }
  }

  Future<void> _toggle(_Reminder reminder, bool enabled) async {
    final index = _items.indexOf(reminder);
    if (index < 0) return;
    final updated = reminder.copyWith(enabled: enabled);
    setState(() => _items[index] = updated);
    await _save();
    await _schedule(updated);
  }

  Future<void> _delete(_Reminder reminder) async {
    await _cancelNotifications(reminder);
    await _deleteSoundChannel(_channelId(reminder));
    if (reminder.soundPath != null) {
      try {
        await File(reminder.soundPath!).delete();
      } catch (_) {}
    }
    setState(() => _items.remove(reminder));
    await _save();
  }

  String _repeatLabel(_Reminder reminder) {
    if (reminder.repeat == 'daily') return 'هر روز';
    if (reminder.repeat == 'weekly') {
      const names = [
        '',
        'دوشنبه',
        'سه‌شنبه',
        'چهارشنبه',
        'پنجشنبه',
        'جمعه',
        'شنبه',
        'یکشنبه',
      ];
      return reminder.days.map((day) => names[day]).join('، ');
    }
    return 'یک‌بار • ${reminder.date}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_alert),
      label: const Text('یادآوری جدید'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
            ? const Center(
                child: Text('هنوز یادآوری‌ای ثبت نکرده‌ای.'),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  if (!_notificationsReady)
                    const Text(
                      'راه‌اندازی اعلان‌ها کامل نشد؛ تنظیمات اعلان گوشی را بررسی کن.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ..._items.map(
                    (reminder) => Card(
                      child: ListTile(
                        isThreeLine: true,
                        title: Text(
                          reminder.text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${reminder.hour.toString().padLeft(2, '0')}:${reminder.minute.toString().padLeft(2, '0')} • ${_repeatLabel(reminder)}${reminder.soundPath == null ? '' : ' • زنگ اختصاصی'}',
                        ),
                        leading: Switch(
                          value: reminder.enabled,
                          onChanged: (value) => _toggle(reminder, value),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) => value == 'edit'
                              ? _edit(reminder)
                              : _delete(reminder),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('ویرایش'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
  );
}
