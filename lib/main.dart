import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Daily reminders tab intentionally left blank.

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Launch the UI first so plugin initialization cannot leave a blank screen.
  tzdata.initializeTimeZones();
  runApp(const TimerApp());

  // Notification setup is non-critical for displaying the app. Run it after
  // startup and catch plugin/platform errors instead of blocking the first frame.
  try {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(initSettings);
  } catch (error, stackTrace) {
    debugPrint('Notification initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
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
      home: const _BiometricGate(),
    );
  }
}


class _BiometricGate extends StatefulWidget {
  const _BiometricGate();

  @override
  State<_BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<_BiometricGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _biometricLockEnabled = true;
  bool _busy = false;
  bool _needsAuthentication = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLockSetting();
  }

  Future<void> _loadLockSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('biometric_lock_enabled') ?? true;
    if (!mounted) return;
    setState(() {
      _biometricLockEnabled = enabled;
      _unlocked = !enabled;
      _needsAuthentication = enabled;
    });
    if (enabled) _authenticate();
  }

  Future<void> _setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_lock_enabled', enabled);
    if (!mounted) return;
    setState(() {
      _biometricLockEnabled = enabled;
      if (!enabled) {
        _unlocked = true;
        _needsAuthentication = false;
        _error = null;
      } else {
        _unlocked = false;
        _needsAuthentication = true;
      }
    });
    if (enabled) _authenticate();
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_unlocked && mounted) {
        setState(() {
          _unlocked = false;
          _needsAuthentication = true;
        });
      }
    } else if (state == AppLifecycleState.resumed &&
        _needsAuthentication && !_busy) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_busy || !mounted || !_biometricLockEnabled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) {
        if (mounted) {
          setState(() {
            _error = 'قفل بیومتریک روی این دستگاه در دسترس نیست. اثر انگشت را در تنظیمات گوشی فعال کن.';
            _busy = false;
          });
        }
        return;
      }

      final available = await _auth.getAvailableBiometrics();
      if (available.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'هیچ اثر انگشتی روی گوشی ثبت نشده است. ابتدا از تنظیمات گوشی اثر انگشت ثبت کن.';
            _busy = false;
          });
        }
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'برای ورود به برنامه زمان‌شمار اثر انگشت خود را تأیید کن',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!mounted) return;
      setState(() {
        _unlocked = authenticated;
        _needsAuthentication = !authenticated;
        _busy = false;
        if (!authenticated) _error = 'تأیید انجام نشد. دوباره تلاش کن.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = false;
        _needsAuthentication = true;
        _error = 'احراز هویت انجام نشد. تنظیمات اثر انگشت گوشی را بررسی کن.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_biometricLockEnabled || _unlocked) {
      return MainScreen(
        biometricLockEnabled: _biometricLockEnabled,
        onToggleBiometricLock: _setLockEnabled,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fingerprint, size: 88, color: Color(0xFF356AE6)),
                const SizedBox(height: 18),
                const Text(
                  'برنامه قفل است',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'برای ورود، اثر انگشت خود را تأیید کن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: _biometricLockEnabled
                      ? FilledButton.icon(
                          onPressed: _busy ? null : () => _setLockEnabled(false),
                          icon: const Icon(Icons.lock),
                          label: const Text('قفل فعال'),
                        )
                      : OutlinedButton.icon(
                          onPressed: _busy ? null : () => _setLockEnabled(true),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('قفل غیرفعال'),
                        ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _busy ? null : _authenticate,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open),
                  label: Text(_busy ? 'در حال بررسی...' : 'تلاش دوباره'),
                ),
              ],
            ),
          ),
        ),
      ),
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

class _PersistentStopwatch {
  Duration _elapsedBefore = Duration.zero;
  DateTime? _runningSince;

  _PersistentStopwatch({
    int elapsedSeconds = 0,
    DateTime? runningSince,
    bool startImmediately = true,
  }) : _elapsedBefore = Duration(seconds: elapsedSeconds),
       _runningSince = runningSince ?? (startImmediately ? DateTime.now() : null);

  bool get isRunning => _runningSince != null;
  Duration get elapsed => _elapsedBefore +
      (_runningSince == null ? Duration.zero : DateTime.now().difference(_runningSince!));

  void start() { _runningSince ??= DateTime.now(); }
  void stop() {
    final since = _runningSince;
    if (since == null) return;
    _elapsedBefore += DateTime.now().difference(since);
    _runningSince = null;
  }

  int get elapsedBeforeSeconds => _elapsedBefore.inSeconds;
  DateTime? get runningSince => _runningSince;
}

class _RunningActivity {
  final String id;
  String name;
  final DateTime startedAt;
  final _PersistentStopwatch stopwatch;
  final TextEditingController nameController = TextEditingController();

  _RunningActivity({
    required this.id,
    required this.name,
    required this.startedAt,
    int elapsedSeconds = 0,
    DateTime? runningSince,
    bool isRunning = true,
  }) : stopwatch = _PersistentStopwatch(
          elapsedSeconds: elapsedSeconds,
          runningSince: runningSince,
          startImmediately: isRunning && runningSince == null,
        ) {
    nameController.text = name;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'elapsedSeconds': stopwatch.elapsedBeforeSeconds,
    'runningSince': stopwatch.runningSince?.millisecondsSinceEpoch,
    'isRunning': stopwatch.isRunning,
  };

  factory _RunningActivity.fromJson(Map<String, dynamic> json) {
    final startedAtMs = json['startedAt'] as int?;
    final runningSinceMs = json['runningSince'] as int?;
    return _RunningActivity(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '',
      startedAt: startedAtMs == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
      runningSince: runningSinceMs == null ? null : DateTime.fromMillisecondsSinceEpoch(runningSinceMs),
      isRunning: json['isRunning'] as bool? ?? false,
    );
  }

  void dispose() { stopwatch.stop(); nameController.dispose(); }
}

class _CountdownTimer {
  final int id;
  String title;
  final int totalSeconds;
  int remainingSeconds;
  DateTime? endsAt;
  DateTime? startedAt;
  bool completionLogged = false;
  bool running = false;
  bool finished = false;
  String? alarmSoundPath;

  _CountdownTimer({
    required this.id, required this.title, required this.totalSeconds,
    int? remainingSeconds, this.endsAt, this.startedAt, this.completionLogged = false,
    this.running = false, this.finished = false, this.alarmSoundPath,
  }) : remainingSeconds = remainingSeconds ?? totalSeconds;

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'totalSeconds': totalSeconds,
    'remainingSeconds': remainingSeconds, 'endsAt': endsAt?.millisecondsSinceEpoch,
    'startedAt': startedAt?.millisecondsSinceEpoch, 'completionLogged': completionLogged,
    'running': running, 'finished': finished, 'alarmSoundPath': alarmSoundPath,
  };

  factory _CountdownTimer.fromJson(Map<String, dynamic> json) {
    final endsAtMs = json['endsAt'] as int?;
    return _CountdownTimer(
      id: json['id'] as int,
      title: json['title'] as String? ?? 'تایمر',
      totalSeconds: json['totalSeconds'] as int,
      remainingSeconds: json['remainingSeconds'] as int?,
      endsAt: endsAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endsAtMs),
      startedAt: (json['startedAt'] as int?) == null ? null : DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
      completionLogged: json['completionLogged'] as bool? ?? false,
      running: json['running'] as bool? ?? false,
      finished: json['finished'] as bool? ?? false,
      alarmSoundPath: json['alarmSoundPath'] as String?,
    );
  }
}


class _ActivityDetailPage extends StatefulWidget {
  final String name;
  final List<_SavedActivity> sessions;
  final Color accentColor;
  final String Function(Duration) formatDuration;
  final String Function(String) persianDigits;
  final Future<_SavedActivity?> Function(_SavedActivity) onEdit;
  final Future<bool> Function(_SavedActivity) onDelete;

  const _ActivityDetailPage({
    required this.name, required this.sessions, required this.accentColor,
    required this.formatDuration, required this.persianDigits,
    required this.onEdit, required this.onDelete,
  });

  @override
  State<_ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<_ActivityDetailPage> {
  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final total = sessions.fold<int>(0, (sum, item) => sum + item.durationSeconds);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold))),
      body: sessions.isEmpty
        ? const Center(child: Text('هنوز سابقه‌ای برای این فعالیت ثبت نشده است.'))
        : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Text('سوابق فعالیت', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: widget.accentColor)),
          const SizedBox(height: 12),
          ...sessions.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text('نوبت ${widget.persianDigits((index + 1).toString())}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: widget.accentColor))),
                    PopupMenuButton<String>(
                      tooltip: 'مدیریت سابقه',
                      onSelected: (value) async {
                        if (value == 'edit') {
                          final edited = await widget.onEdit(item);
                          if (edited != null && mounted) setState(() {
                            final i = widget.sessions.indexOf(item);
                            if (i >= 0) widget.sessions[i] = edited;
                          });
                        }
                        if (value == 'delete') {
                          final deleted = await widget.onDelete(item);
                          if (deleted && mounted) setState(() => widget.sessions.remove(item));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined), SizedBox(width: 8), Text('ویرایش')])),
                        PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red), SizedBox(width: 8), Text('حذف', style: TextStyle(color: Colors.red))])),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFFF7F8FC), borderRadius: BorderRadius.circular(12)),
                    child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true,
                      child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: Colors.black87), children: [
                        const TextSpan(text: 'شروع: ', style: TextStyle(color: Colors.black54)),
                        TextSpan(text: '${item.startDate} - ${item.startTime}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const TextSpan(text: '   |   پایان: ', style: TextStyle(color: Colors.black54)),
                        TextSpan(text: '${item.endDate} - ${item.endTime}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const TextSpan(text: '   |   مدت: ', style: TextStyle(color: Colors.black54)),
                        TextSpan(text: widget.formatDuration(Duration(seconds: item.durationSeconds)),
                          style: TextStyle(fontWeight: FontWeight.bold, color: widget.accentColor)),
                      ]), maxLines: 1, softWrap: false),
                    ),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 8),
          Card(color: widget.accentColor.withValues(alpha: 0.09), elevation: 0,
            child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
              const Text('مجموع کل زمان این فعالیت', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(widget.formatDuration(Duration(seconds: total)), textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: widget.accentColor)),
              const SizedBox(height: 4),
              Text('تعداد دفعات: ${widget.persianDigits(sessions.length.toString())}',
                style: const TextStyle(color: Colors.black54)),
            ])),
          ),
        ]),
    );
  }
}


class _SavedAlarm {
 int id; String title; int hour,minute; DateTime date; List<int> weekdays; String? sound; bool enabled;
 _SavedAlarm({required this.id,required this.title,required this.hour,required this.minute,required this.date,required this.weekdays,this.sound,this.enabled=true});
 Map<String,dynamic> toJson()=>{'id':id,'title':title,'hour':hour,'minute':minute,'date':date.toIso8601String(),'weekdays':weekdays,'sound':sound,'enabled':enabled};
 factory _SavedAlarm.fromJson(Map<String,dynamic> j)=>_SavedAlarm(id:j['id'] as int,title:j['title'] as String? ?? 'زنگ هشدار',hour:j['hour'] as int? ?? 8,minute:j['minute'] as int? ?? 0,date:DateTime.tryParse(j['date'] as String? ?? '')??DateTime.now(),weekdays:(j['weekdays'] as List? ?? []).map((x)=>x as int).toList(),sound:j['sound'] as String?,enabled:j['enabled'] as bool? ?? true);
}
class _DailyReminder {
  int id;
  String text;
  DateTime scheduledAt;
  String? soundPath;
  _DailyReminder({required this.id, required this.text, required this.scheduledAt, this.soundPath});
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'scheduledAt': scheduledAt.toIso8601String(), 'soundPath': soundPath};
  factory _DailyReminder.fromJson(Map<String, dynamic> json) => _DailyReminder(id: json['id'] as int, text: json['text'] as String? ?? '', scheduledAt: DateTime.tryParse(json['scheduledAt'] as String? ?? '') ?? DateTime.now(), soundPath: json['soundPath'] as String?);
}

class _AlarmsPage extends StatefulWidget { const _AlarmsPage(); @override State<_AlarmsPage> createState()=>_AlarmsPageState(); }
class _AlarmsPageState extends State<_AlarmsPage>{
 static const key='independent_alarms_v1'; final items=<_SavedAlarm>[]; final player=AudioPlayer(); bool loading=true;
 @override void initState(){super.initState();load();}
 @override void dispose(){player.dispose();super.dispose();}
 Future<void> load()async{final p=await SharedPreferences.getInstance();final raw=p.getString(key);if(raw!=null){try{items.addAll((jsonDecode(raw) as List).map((x)=>_SavedAlarm.fromJson(Map<String,dynamic>.from(x))));}catch(_){}}if(mounted)setState(()=>loading=false);for(final a in items.where((a)=>a.enabled)){await schedule(a);}}
 Future<void> save()async{final p=await SharedPreferences.getInstance();await p.setString(key,jsonEncode(items.map((a)=>a.toJson()).toList()));}
 int nid(_SavedAlarm a,int d)=>700000+a.id*10+d;
 Future<void> cancel(_SavedAlarm a)async{for(var d=0;d<=7;d++)await _notifications.cancel(nid(a,d));}
 NotificationDetails details()=>const NotificationDetails(android:AndroidNotificationDetails('independent_alarm_channel','زنگ‌های مستقل',channelDescription:'زنگ هشدارهای شخصی',importance:Importance.max,priority:Priority.max,category:AndroidNotificationCategory.alarm,playSound:true,audioAttributesUsage:AudioAttributesUsage.alarm));
 Future<void> schedule(_SavedAlarm a)async{await cancel(a);if(!a.enabled)return;final now=DateTime.now();if(a.weekdays.isEmpty){final dt=DateTime(a.date.year,a.date.month,a.date.day,a.hour,a.minute);if(!dt.isAfter(now))return;await _notifications.zonedSchedule(nid(a,0),a.title,'زمان هشدار فرا رسیده است',tz.TZDateTime.from(dt,tz.local),details(),androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,payload:'personal-alarm:${a.id}');}else{for(final wd in a.weekdays){var dt=DateTime(now.year,now.month,now.day,a.hour,a.minute);while(dt.weekday!=wd||!dt.isAfter(now)){dt=dt.add(const Duration(days:1));dt=DateTime(dt.year,dt.month,dt.day,a.hour,a.minute);}await _notifications.zonedSchedule(nid(a,wd),a.title,'زمان هشدار فرا رسیده است',tz.TZDateTime.from(dt,tz.local),details(),androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,matchDateTimeComponents:DateTimeComponents.dayOfWeekAndTime,payload:'personal-alarm:${a.id}');}}}
 String time(_SavedAlarm a)=>'${a.hour.toString().padLeft(2,'0')}:${a.minute.toString().padLeft(2,'0')}';
 String repeat(_SavedAlarm a)=>a.weekdays.isEmpty?'یک‌بار • ${a.date.year}/${a.date.month}/${a.date.day}':a.weekdays.map((d)=>['','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'][d]).join('، ');
 Future<void> edit(_SavedAlarm? old)async{final ctl=TextEditingController(text:old?.title??'');var h=old?.hour??8,m=old?.minute??0,dt=old?.date??DateTime.now();List<int> days=[...(old?.weekdays??[])];var sound=old?.sound;const labels=['دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'];
 final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,upd)=>AlertDialog(title:Text(old==null?'زنگ جدید':'ویرایش زنگ'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:ctl,decoration:const InputDecoration(labelText:'عنوان')),ListTile(title:Text('ساعت ${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}'),onTap:()async{final t=await showTimePicker(context:ctx,initialTime:TimeOfDay(hour:h,minute:m));if(t!=null)upd(() {h=t.hour;m=t.minute;});}),ListTile(title:Text('تاریخ ${dt.year}/${dt.month}/${dt.day}'),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:dt.isBefore(DateTime.now())?DateTime.now():dt,firstDate:DateTime.now(),lastDate:DateTime(2100));if(d!=null)upd(()=>dt=d);}),const Text('تکرار هفتگی (برای یک‌بار روزها را خالی بگذار)'),Wrap(children:List.generate(7,(i)=>FilterChip(label:Text(labels[i]),selected:days.contains(i+1),onSelected:(v)=>upd(()=>v?days.add(i+1):days.remove(i+1))))),OutlinedButton.icon(onPressed:()async{final f=await FilePicker.pickFile(type:FileType.audio);if(f?.path==null)return;final dir=await getApplicationSupportDirectory();final ext=f!.path!.split('.').last;final dest=File('${dir.path}/personal_alarm_${old?.id??DateTime.now().millisecondsSinceEpoch}.$ext');await File(f.path!).copy(dest.path);sound=dest.path;upd((){});},icon:const Icon(Icons.music_note),label:Text(sound==null?'انتخاب فایل زنگ':'تغییر فایل زنگ')),if(sound!=null)TextButton.icon(onPressed:()async{await player.stop();await player.play(DeviceFileSource(sound!));},icon:const Icon(Icons.play_arrow),label:const Text('پیش‌نمایش زنگ')),const Text('فایل زنگ برای هر هشدار جدا ذخیره می‌شود. اعلان زمان‌بندی‌شده در پس‌زمینه از صدای اعلان سیستم استفاده می‌کند.',style:TextStyle(fontSize:12,color:Colors.black54))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ذخیره'))])));
 if(ok!=true)return;final a=old??_SavedAlarm(id:DateTime.now().millisecondsSinceEpoch%1000000,title:'',hour:h,minute:m,date:dt,weekdays:days);a.title=ctl.text.trim().isEmpty?'زنگ هشدار':ctl.text.trim();a.hour=h;a.minute=m;a.date=dt;a.weekdays=[...days]..sort();a.sound=sound;if(old==null)items.add(a);await save();await schedule(a);if(mounted)setState((){});
 }
 Future<void> toggle(_SavedAlarm a,bool v)async{a.enabled=v;await save();await schedule(a);setState((){});}
 Future<void> remove(_SavedAlarm a)async{await cancel(a);items.remove(a);await save();setState((){});}
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('زنگ هشدارها')),
  floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(null),icon:const Icon(Icons.add_alarm),label:const Text('زنگ جدید')),
  body:loading?const Center(child:CircularProgressIndicator()):ListView(
    padding:const EdgeInsets.fromLTRB(12,12,12,90),
    children:[
      const _AlarmCountdownPanel(),
      const SizedBox(height:12),
      if(items.isEmpty) const Padding(padding:EdgeInsets.all(20),child:Center(child:Text('هنوز زنگی ثبت نشده است.'))),
      ...items.map((a)=>Card(child:ListTile(
        leading:Icon(Icons.alarm,color:a.enabled?Theme.of(context).colorScheme.primary:Colors.grey),
        title:Text(time(a),textDirection:TextDirection.ltr,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
        subtitle:Text('${a.title}\\n${repeat(a)}${a.sound==null?'':'\\nفایل زنگ ذخیره شده'}'),
        isThreeLine:true,
        trailing:Wrap(children:[
          Switch(value:a.enabled,onChanged:(v)=>toggle(a,v)),
          IconButton(icon:const Icon(Icons.edit),onPressed:()=>edit(a)),
          IconButton(icon:const Icon(Icons.delete_outline,color:Colors.red),onPressed:()=>remove(a)),
        ]),
      ))),
    ],
  ),
);

}

class _AlarmCountdownPanel extends StatefulWidget {
 const _AlarmCountdownPanel();
 @override State<_AlarmCountdownPanel> createState()=>_AlarmCountdownPanelState();
}
class _AlarmCountdownPanelState extends State<_AlarmCountdownPanel>{
 final hController=TextEditingController(text:'0');
 final mController=TextEditingController(text:'5');
 final sController=TextEditingController(text:'0');
 Timer? ticker;
 int remaining=0;
 DateTime? endsAt;
 bool running=false;
 @override void dispose(){ticker?.cancel();hController.dispose();mController.dispose();sController.dispose();super.dispose();}
 String display(int value)=>'${(value~/3600).toString().padLeft(2,'0')}:${((value%3600)~/60).toString().padLeft(2,'0')}:${(value%60).toString().padLeft(2,'0')}';
 Future<void> start() async {
   if(running)return;
   if(remaining<=0){final h=int.tryParse(hController.text)??0;final m=int.tryParse(mController.text)??0;final s=int.tryParse(sController.text)??0;remaining=h*3600+m*60+s;}
   if(remaining<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('زمانی بیشتر از صفر وارد کن.')));return;}
   endsAt=DateTime.now().add(Duration(seconds:remaining));
   setState(()=>running=true);
   try{await _notifications.zonedSchedule(880001,'پایان تایمر معکوس','زمان شمارش معکوس به پایان رسید.',tz.TZDateTime.from(endsAt!,tz.local),const NotificationDetails(android:AndroidNotificationDetails('alarm_countdown_section','تایمر بخش هشدارها',channelDescription:'اعلان پایان شمارش معکوس',importance:Importance.max,priority:Priority.max,playSound:true,enableVibration:true,category:AndroidNotificationCategory.alarm)),androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle);}catch(_){}
   ticker?.cancel();
   ticker=Timer.periodic(const Duration(seconds:1),(t){
     if(!mounted)return;
     if(remaining<=1){t.cancel();_notifications.cancel(880001);endsAt=null;setState(()=>remaining=0);setState(()=>running=false);_notifyFinish();return;}
     setState(()=>remaining--);
   });
 }
 void pause(){ticker?.cancel();_notifications.cancel(880001);if(endsAt!=null){remaining=endsAt!.difference(DateTime.now()).inSeconds.clamp(0,remaining).toInt();}endsAt=null;setState(()=>running=false);}
 void reset(){ticker?.cancel();_notifications.cancel(880001);endsAt=null;final h=int.tryParse(hController.text)??0;final m=int.tryParse(mController.text)??0;final s=int.tryParse(sController.text)??0;setState(()=>running=false);setState(()=>remaining=h*3600+m*60+s);}
 Future<void> _notifyFinish()async{
   try{await _notifications.show(880001,'پایان تایمر معکوس','زمان شمارش معکوس به پایان رسید.',const NotificationDetails(android:AndroidNotificationDetails('alarm_countdown_section','تایمر بخش هشدارها',channelDescription:'اعلان پایان شمارش معکوس',importance:Importance.max,priority:Priority.max,playSound:true,enableVibration:true,category:AndroidNotificationCategory.alarm)));}catch(_){}
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('زمان تایمر به پایان رسید!')));
 }
 Widget numberField(String label,TextEditingController c)=>SizedBox(width:70,child:TextField(controller:c,keyboardType:TextInputType.number,textAlign:TextAlign.center,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),enabled:!running,onChanged:(_)=>reset()));
 @override Widget build(BuildContext context)=>Card(
   child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Row(children:[Icon(Icons.hourglass_bottom,color:Theme.of(context).colorScheme.primary),const SizedBox(width:8),const Text('تایمر معکوس',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))]),
     const SizedBox(height:12),
     if(!running&&remaining==0)Row(mainAxisAlignment:MainAxisAlignment.center,children:[numberField('ساعت',hController),const SizedBox(width:8),numberField('دقیقه',mController),const SizedBox(width:8),numberField('ثانیه',sController)]),
     const SizedBox(height:8),
     Center(child:Text(display(remaining),textDirection:TextDirection.ltr,style:TextStyle(fontSize:34,fontWeight:FontWeight.bold,color:Theme.of(context).colorScheme.primary))),
     const SizedBox(height:10),
     Row(mainAxisAlignment:MainAxisAlignment.center,children:[
       if(!running)FilledButton.icon(onPressed:start,icon:const Icon(Icons.play_arrow),label:Text(remaining>0?'ادامه':'شروع')),
       if(running)FilledButton.icon(onPressed:pause,icon:const Icon(Icons.pause),label:const Text('مکث')),
       const SizedBox(width:8),
       OutlinedButton.icon(onPressed:reset,icon:const Icon(Icons.restart_alt),label:const Text('بازنشانی')),
     ]),
     const Text('در پایان زمان، اعلان هشدار نمایش داده می‌شود.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Colors.black54)),
   ])),
 );
}
class _RenameCountdownDialog extends StatefulWidget {
  final String initialName;

  const _RenameCountdownDialog({required this.initialName});

  @override
  State<_RenameCountdownDialog> createState() => _RenameCountdownDialogState();
}

class _RenameCountdownDialogState extends State<_RenameCountdownDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغییر نام تایمر'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textDirection: TextDirection.rtl,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'نام تایمر',
          hintText: 'مثلاً ساعت خواب',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('لغو'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

class MainScreen extends StatefulWidget {
  final bool biometricLockEnabled;
  final Future<void> Function(bool) onToggleBiometricLock;
  const MainScreen({super.key, required this.biometricLockEnabled, required this.onToggleBiometricLock});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _storageKey = 'completed_activities_jalali_v1';
  static const _namesStorageKey = 'activity_names_v1';
  static const _categoriesStorageKey = 'activity_categories_v1';
  static const _runningActivitiesStorageKey = 'running_activities_v1';
  static const _countdownsStorageKey = 'countdown_timers_v1';
  static const _dailyRemindersStorageKey = 'daily_reminders_simple_v1';
  static const _tabTitles = ['ثبت زمان', 'فعالیت‌ها', 'گزارش‌گیری', 'تایمر معکوس', 'یادآوری‌های روزانه'];
  static const _colors = [
    Color(0xFF356AE6),
    Color(0xFF00897B),
    Color(0xFF8E44AD),
    Color(0xFFE07828),
    Color(0xFFCE496B),
    Color(0xFF34495E),
  ];

  int _selectedIndex = 0;
  bool _activitiesGroupedView = true;
  String? _openedActivityFolder;
  Color _accentColor = _colors.first;
  DateTime _now = DateTime.now();
  static const _clockOffsetStorageKey = 'program_clock_offset_minutes_v1';
  int _clockOffsetMinutes = 0;

  DateTime get _programNow => DateTime.now().add(Duration(minutes: _clockOffsetMinutes));
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;
  final Set<String> _reportSelectedNames = {};
  final List<_CountdownTimer> _countdowns=[];
  final List<_DailyReminder> _dailyReminders = [];
  int _nextDailyReminderId = 850000;
  final AudioPlayer _dailyReminderPreviewPlayer = AudioPlayer();
  Timer? _countdownTicker;
  int _wheelHours=0, _wheelMinutes=5, _wheelSeconds=0, _nextCountdownId=1000;
  late final FixedExtentScrollController _hoursWheelController;
  late final FixedExtentScrollController _minutesWheelController;
  late final FixedExtentScrollController _secondsWheelController;
  bool _countdownAlarmEnabled = true;
  bool _countdownAlarmSound = true;
  bool _countdownAlarmVibration = true;
  String? _customAlarmSoundPath;
  final AudioPlayer _customAlarmPlayer = AudioPlayer();
  Timer? _clock;
  final List<_RunningActivity> _runningActivities = [];
  List<_SavedActivity> _savedActivities = [];
  List<String> _activityNames = [];
  Map<String, String> _activityCategories = {};
  List<String> _activityCategoryNames = [];

  @override
  void initState() {
    super.initState();
    _hoursWheelController = FixedExtentScrollController(initialItem: _wheelHours);
    _minutesWheelController = FixedExtentScrollController(initialItem: _wheelMinutes);
    _secondsWheelController = FixedExtentScrollController(initialItem: _wheelSeconds);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _programNow);
    });
    _loadProgramClockSettings();
    _initializeData();
    _clearRemovedChecklistData();
    _initializeAlarmNotifications();
    _countdownTicker=Timer.periodic(const Duration(seconds:1), (_) => _tickCountdowns());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _countdownTicker?.cancel();
    _customAlarmPlayer.dispose();
    _dailyReminderPreviewPlayer.dispose();
    _hoursWheelController.dispose();
    _minutesWheelController.dispose();
    _secondsWheelController.dispose();
    for (final activity in _runningActivities) {
      activity.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _loadActivities();
    await _loadActivityNames();
    await _loadActivityCategories();
    await _restoreRunningActivities();
  }

  Future<void> _persistRunningActivities() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_runningActivitiesStorageKey,
        jsonEncode(_runningActivities.map((item) => item.toJson()).toList()));
  }

  Future<void> _restoreRunningActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_runningActivitiesStorageKey);
    if (raw == null || !mounted) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = decoded.map((item) =>
          _RunningActivity.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      if (!mounted) { for (final item in restored) { item.dispose(); } return; }
      setState(() { _runningActivities..clear()..addAll(restored); });
    } catch (_) {
      // Ignore a damaged local running-timer cache.
    }
  }

  Future<String?> _askChecklistText({
    required String title,
    required String hint,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    controller.dispose();
    return result;
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

  Future<void> _loadActivityCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_categoriesStorageKey);
    Map<String, String> loadedCategories = {};
    if (raw != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        loadedCategories = decoded.map((k, v) => MapEntry(k, v.toString() == 'بدون دسته‌بندی' ? 'بدون پوشه' : v.toString()));
      } catch (_) {
        // Keep the category-name list even if the category mapping is damaged.
      }
    }
    final storedNames = prefs.getStringList('activity_category_names_v1') ?? [];
    if (!mounted) return;
    setState(() {
      _activityCategories = loadedCategories;
      _activityCategoryNames = <String>{
        ...loadedCategories.values.where((v) => v != 'بدون پوشه' && v != 'بدون دسته‌بندی'),
        ...storedNames,
      }.toList()..sort();
    });
  }

  Future<void> _persistActivityCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_categoriesStorageKey, jsonEncode(_activityCategories));
  }

  Future<void> _setActivityCategory(String name) async {
    final current = _activityCategories[name] ?? 'بدون پوشه';
    final category = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('انتقال به پوشه'),
        content: SizedBox(
          width: double.maxFinite,
          child: _activityCategoryNames.isEmpty
              ? const Text('هنوز پوشه‌ای ایجاد نشده است. ابتدا از «مدیریت پوشه‌ها» یک پوشه بساز.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    ..._activityCategoryNames.map((folder) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder),
                      trailing: current == folder ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () => Navigator.pop(ctx, folder),
                    )),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.folder_off_outlined),
                      title: const Text('بدون پوشه'),
                      trailing: current == 'بدون پوشه' ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () => Navigator.pop(ctx, 'بدون پوشه'),
                    ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
      ),
    );
    if (category == null || !mounted) return;
    setState(() => _activityCategories[name] = category);
    await _persistActivityCategories();
  }

  Future<void> _persistActivityCategoryNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('activity_category_names_v1', _activityCategoryNames);
  }

  Future<void> _manageActivityCategories() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        title: const Text('مدیریت پوشه‌ها'),
        content: SizedBox(width: double.maxFinite, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'نام پوشه جدید'))),
              IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty || _activityCategoryNames.any((c) => c.toLowerCase() == name.toLowerCase())) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('نام پوشه خالی یا تکراری است.')));
                  return;
                }
                setState(() { _activityCategoryNames.add(name); _activityCategoryNames.sort(); });
                controller.clear(); refresh(() {});
                _persistActivityCategoryNames();
              }),
            ]),
            const Divider(),
            if (_activityCategoryNames.isEmpty) const Text('هنوز پوشه‌ای ایجاد نشده است.'),
            ..._activityCategoryNames.map((category) => ListTile(
              dense: true, title: Text(category),
              subtitle: Text('${_activityNames.where((n) => (_activityCategories[n] ?? 'بدون پوشه') == category).length} فعالیت'),
              trailing: Wrap(children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
                  final edited = await _askChecklistText(title: 'ویرایش پوشه', hint: 'نام پوشه', initial: category);
                  if (edited == null || edited.trim().isEmpty || !mounted) return;
                  final newName = edited.trim();
                  if (newName != category && _activityCategoryNames.any((c) => c.toLowerCase() == newName.toLowerCase())) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('پوشه‌ای با این نام وجود دارد.')));
                    return;
                  }
                  setState(() {
                    _activityCategoryNames = _activityCategoryNames.map<String>((c) => c == category ? newName : c).toSet().toList()..sort();
                    _activityCategories.updateAll((key, value) => value == category ? newName : value);
                    if (_openedActivityFolder == category) _openedActivityFolder = newName;
                  });
                  await _persistActivityCategoryNames(); await _persistActivityCategories();
                  refresh(() {});
                }),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async {
                  final ok = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(
                    title: const Text('حذف پوشه'),
                    content: Text('پوشه «$category» حذف شود؟ فعالیت‌های آن به «بدون پوشه» منتقل می‌شوند.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))],
                  ));
                  if (ok != true || !mounted) return;
                  setState(() {
                    _activityCategoryNames.remove(category);
                    _activityCategories.updateAll((key, value) => value == category ? 'بدون پوشه' : value);
                    if (_openedActivityFolder == category) _openedActivityFolder = null;
                  });
                  await _persistActivityCategoryNames(); await _persistActivityCategories();
                  refresh(() {});
                }),
              ]),
            )),
          ],
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
      )),
    );
    controller.dispose();
  }

  Future<void> _editActivityName(String oldName) async {
    final edited = await _askChecklistText(title: 'ویرایش فعالیت', hint: 'نام فعالیت', initial: oldName);
    if (edited == null || edited.trim().isEmpty || !mounted) return;
    final newName = edited.trim();
    if (newName != oldName && _activityNames.any((n) => n.toLowerCase() == newName.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این نام قبلاً استفاده شده است.')));
      return;
    }
    setState(() {
      _activityNames = _activityNames.map<String>((n) => n == oldName ? newName : n).toList()..sort();
      if (_activityCategories.containsKey(oldName)) {
        _activityCategories[newName] = _activityCategories.remove(oldName)!;
      }
      _savedActivities = _savedActivities.map((a) => a.name == oldName ? _SavedActivity(
        name: newName, startDate: a.startDate, startTime: a.startTime,
        endDate: a.endDate, endTime: a.endTime, durationSeconds: a.durationSeconds,
      ) : a).toList();
      for (final running in _runningActivities.where((a) => a.name == oldName)) {
        running.name = newName; running.nameController.text = newName;
      }
    });
    await _persistActivityNames(); await _persistActivityCategories(); await _persistActivities();
  }

  Future<void> _deleteActivity(String name) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف فعالیت'),
      content: Text('فعالیت «$name» و تمام سوابق زمانی آن حذف شوند؟ این کار قابل بازگشت نیست.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))],
    ));
    if (ok != true || !mounted) return;
    setState(() {
      _activityNames.remove(name); _activityCategories.remove(name);
      _savedActivities.removeWhere((a) => a.name == name);
      final running = _runningActivities.where((a) => a.name == name).toList();
      for (final item in running) { _runningActivities.remove(item); item.dispose(); }
    });
    await _persistActivityNames(); await _persistActivityCategories(); await _persistActivities();
  }

  Future<void> _openActivityDetails(String name) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ActivityDetailPage(
        name: name,
        sessions: _savedActivities.where((a) => a.name == name).toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate)),
        accentColor: _accentColor,
        formatDuration: _durationText,
        persianDigits: _persianDigits,
        onEdit: _editSavedActivity,
        onDelete: _deleteSavedActivity,
      ),
    ));
  }

  Future<_SavedActivity?> _editSavedActivity(_SavedActivity activity) async {
    final index = _savedActivities.indexOf(activity);
    if (index < 0) return null;
    final hours = TextEditingController(text: (activity.durationSeconds ~/ 3600).toString());
    final minutes = TextEditingController(text: ((activity.durationSeconds % 3600) ~/ 60).toString());
    final seconds = TextEditingController(text: (activity.durationSeconds % 60).toString());
    final startDate = TextEditingController(text: activity.startDate);
    final startTime = TextEditingController(text: activity.startTime);
    final endDate = TextEditingController(text: activity.endDate);
    final endTime = TextEditingController(text: activity.endTime);
    final result = await showDialog<_SavedActivity>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش سابقه زمانی'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('مدت زمان'),
          Row(children: [
            Expanded(child: TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ساعت'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'دقیقه'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: seconds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ثانیه'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: startDate, decoration: const InputDecoration(labelText: 'تاریخ شروع')),
          TextField(controller: startTime, decoration: const InputDecoration(labelText: 'ساعت شروع')),
          TextField(controller: endDate, decoration: const InputDecoration(labelText: 'تاریخ پایان')),
          TextField(controller: endTime, decoration: const InputDecoration(labelText: 'ساعت پایان')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () {
            final h = int.tryParse(hours.text.trim());
            final m = int.tryParse(minutes.text.trim());
            final sec = int.tryParse(seconds.text.trim());
            if (h == null || m == null || sec == null || h < 0 || m < 0 || sec < 0 ||
                m > 59 || sec > 59 || h + m + sec == 0 ||
                startDate.text.trim().isEmpty || startTime.text.trim().isEmpty ||
                endDate.text.trim().isEmpty || endTime.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('اطلاعات زمان را به‌درستی وارد کن.')));
              return;
            }
            Navigator.pop(ctx, _SavedActivity(
              name: activity.name,
              startDate: startDate.text.trim(), startTime: startTime.text.trim(),
              endDate: endDate.text.trim(), endTime: endTime.text.trim(),
              durationSeconds: h * 3600 + m * 60 + sec,
            ));
          }, child: const Text('ذخیره تغییرات')),
        ],
      ),
    );
    for (final c in [hours, minutes, seconds, startDate, startTime, endDate, endTime]) { c.dispose(); }
    if (result == null || !mounted) return null;
    setState(() => _savedActivities[index] = result);
    await _persistActivities();
    return result;
  }

  Future<bool> _deleteSavedActivity(_SavedActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سابقه زمانی'),
        content: Text('سابقه «${activity.name}» حذف شود؟ این کار قابل بازگشت نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    setState(() => _savedActivities.remove(activity));
    await _persistActivities();
    return true;
  }

  Future<void> _persistActivityNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_namesStorageKey, _activityNames);
  }

  Future<void> _addManualActivityTime(String name) async {
    final hoursController = TextEditingController();
    final minutesController = TextEditingController();
    final secondsController = TextEditingController();

    final durationSeconds = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ثبت زمان دستی برای «$name»'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('مدت زمانی را که برای این فعالیت صرف کرده‌ای وارد کن.'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(
                  controller: hoursController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'ساعت', border: OutlineInputBorder()),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: minutesController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'دقیقه', border: OutlineInputBorder()),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: secondsController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'ثانیه', border: OutlineInputBorder()),
                )),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final hours = int.tryParse(hoursController.text.trim()) ?? 0;
              final minutes = int.tryParse(minutesController.text.trim()) ?? 0;
              final seconds = int.tryParse(secondsController.text.trim()) ?? 0;
              if (hours < 0 || minutes < 0 || seconds < 0 ||
                  (hours == 0 && minutes == 0 && seconds == 0)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('مدت زمان معتبر و بیشتر از صفر وارد کن.')),
                );
                return;
              }
              Navigator.pop(dialogContext, hours * 3600 + minutes * 60 + seconds);
            },
            child: const Text('ثبت زمان'),
          ),
        ],
      ),
    );

    hoursController.dispose();
    minutesController.dispose();
    secondsController.dispose();
    if (durationSeconds == null || !mounted) return;

    final endedAt = _programNow;
    final startedAt = endedAt.subtract(Duration(seconds: durationSeconds));
    setState(() {
      _savedActivities.insert(0, _SavedActivity(
        name: name,
        startDate: _jalaliDate(startedAt),
        startTime: _clockTime(startedAt),
        endDate: _jalaliDate(endedAt),
        endTime: _clockTime(endedAt),
        durationSeconds: durationSeconds,
      ));
    });
    await _persistActivities();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('زمان دستی فعالیت «$name» ثبت شد.')),
    );
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
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),        ),        actions: [
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

  Future<void> _startNewActivity(String name) async {
    if (name.trim().isEmpty) return;
    final existing = _runningActivities.where((a) => a.name.trim().toLowerCase() == name.trim().toLowerCase()).firstOrNull;
    if (existing != null) {
      if (!existing.stopwatch.isRunning) await _startActivity(existing);
      return;
    }
    final activity = _RunningActivity(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      startedAt: _programNow,
    );
    setState(() => _runningActivities.insert(0, activity));
    await _persistRunningActivities();
  }

  Future<void> _createActivityTimer() async {
    final activity = _RunningActivity(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '',
      startedAt: _programNow,
    );
    setState(() => _runningActivities.insert(0, activity));
    await _persistRunningActivities();
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
    await _persistRunningActivities();
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

  Future<void> _startActivity(_RunningActivity activity) async {
    if (activity.stopwatch.isRunning) return;
    setState(() => activity.stopwatch.start());
    await _persistRunningActivities();
  }

  Future<void> _pauseActivity(_RunningActivity activity) async {
    if (!activity.stopwatch.isRunning) return;
    setState(() => activity.stopwatch.stop());
    await _persistRunningActivities();
  }

  Future<void> _deleteRunningActivity(_RunningActivity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف فعالیت'),
        content: Text('فعالیت «${activity.nameController.text.trim().isEmpty ? 'بدون نام' : activity.nameController.text.trim()}» حذف شود؟ زمان آن ذخیره نخواهد شد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _runningActivities.removeWhere((item) => item.id == activity.id);
    });
    activity.dispose();
    await _persistRunningActivities();
  }

  Future<void> _stopActivity(_RunningActivity activity) async {
    activity.stopwatch.stop();
    final endedAt = _programNow;
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
    await _persistRunningActivities();
    await _persistActivities();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('فعالیت «${activity.name}» ذخیره شد')),
    );
  }

  Future<void> _loadProgramClockSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final offset = prefs.getInt(_clockOffsetStorageKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _clockOffsetMinutes = offset;
      _now = _programNow;
    });
  }

  Future<void> _showProgramClockSettings() async {
    final current = _programNow;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'ساعت موردنظر برای برنامه را انتخاب کن',
      confirmText: 'ثبت ساعت',
      cancelText: 'انصراف',
    );
    if (selected == null || !mounted) return;
    final realNow = DateTime.now();
    final selectedMinutes = selected.hour * 60 + selected.minute;
    final realMinutes = realNow.hour * 60 + realNow.minute;
    var offset = selectedMinutes - realMinutes;
    if (offset > 720) offset -= 1440;
    if (offset < -720) offset += 1440;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clockOffsetStorageKey, offset);
    if (!mounted) return;
    setState(() {
      _clockOffsetMinutes = offset;
      _now = _programNow;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ساعت برنامه روی ${_clockTime(_now, withSeconds: false)} تنظیم شد.')),
    );
  }

  Future<void> _resetProgramClock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clockOffsetStorageKey);
    if (!mounted) return;
    setState(() {
      _clockOffsetMinutes = 0;
      _now = DateTime.now();
    });
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
          IconButton(
            tooltip: widget.biometricLockEnabled ? 'غیرفعال کردن قفل برنامه' : 'فعال کردن قفل برنامه',
            onPressed: () => widget.onToggleBiometricLock(!widget.biometricLockEnabled),
            icon: Icon(widget.biometricLockEnabled ? Icons.lock_rounded : Icons.lock_open_rounded),
            color: widget.biometricLockEnabled ? _accentColor : Colors.black45,
          ),
          IconButton(
            tooltip: 'گزارش‌گیری',
            onPressed: () => setState(() => _selectedIndex = 2),
            icon: Icon(_selectedIndex == 2 ? Icons.bar_chart_rounded : Icons.bar_chart_outlined),
          ),
          if (_selectedIndex == 0) ...[
            IconButton(
              tooltip: 'تنظیم ساعت برنامه',
              onPressed: _showProgramClockSettings,
              icon: const Icon(Icons.schedule_outlined),
            ),
            IconButton(
              tooltip: 'بازگشت به ساعت واقعی',
              onPressed: _clockOffsetMinutes == 0 ? null : _resetProgramClock,
              icon: const Icon(Icons.restore),
            ),
            IconButton(
              tooltip: 'تنظیم رنگ‌ها',
              onPressed: _showColorSettings,
              icon: const Icon(Icons.palette_outlined),
            ),
          ],
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildTimeEntryPage(),
          _buildActivitiesPage(),
          _buildReportsPage(),
          _buildCountdownPage(),
          _buildDailyRemindersPage(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NavigationBar(
        selectedIndex: _selectedIndex >= 3 ? _selectedIndex - 1 : (_selectedIndex == 2 ? 1 : _selectedIndex),
        onDestinationSelected: (index) => setState(() => _selectedIndex = index >= 2 ? index + 1 : index),
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
            icon: Icon(Icons.hourglass_bottom_rounded),
            selectedIcon: Icon(Icons.hourglass_full_rounded),
            label: 'تایمر معکوس',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active_rounded),
            label: 'یادآوری‌های روزانه',
          ),
        ],
      ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeEntryPage() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: [
                // ساعت و تاریخ در بالای صفحه، جدا از کنترل‌های فعالیت
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _persianDigits(_jalaliDate(_now)),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _clockTime(_now),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'ساعت فعلی',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_runningActivities.isNotEmpty) ...[
                  ..._runningActivities.map(_buildRunningActivityCard),
                  const SizedBox(height: 10),
                ],
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _createActivityTimer,
                      icon: const Icon(Icons.add_rounded, size: 23),
                      label: const Text(
                        'فعالیت جدید',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunningActivityCard(_RunningActivity activity) {
    final isRunning = activity.stopwatch.isRunning;
    final elapsed = activity.stopwatch.elapsed;
    final compactCounter = _persianDigits(
      '${_twoDigits(elapsed.inHours)}:${_twoDigits(elapsed.inMinutes.remainder(60))}:${_twoDigits(elapsed.inSeconds.remainder(60))}',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE8EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'ذخیره نام فعالیت',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 36),
              padding: EdgeInsets.zero,
              onPressed: () => _saveActivityName(activity),
              icon: const Icon(Icons.save_outlined, size: 18),
              color: _accentColor,
            ),
            IconButton(
              tooltip: 'حذف فعالیت',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 36),
              padding: EdgeInsets.zero,
              onPressed: () => _deleteRunningActivity(activity),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: Colors.redAccent,
            ),
            Expanded(
              flex: 5,
              child: TextField(
                controller: activity.nameController,
                textInputAction: TextInputAction.done,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF252A34),
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: 'نام فعالیت',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (value) {
                  activity.name = value;
                },
                onSubmitted: (_) => _saveActivityName(activity),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: 3,
              child: Text(
                compactCounter,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: _accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              tooltip: 'شروع',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              padding: EdgeInsets.zero,
              onPressed: isRunning ? null : () => _startActivity(activity),
              icon: const Icon(Icons.play_arrow_rounded, size: 25),
              color: Colors.green,
            ),
            IconButton(
              tooltip: 'مکث',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              padding: EdgeInsets.zero,
              onPressed: isRunning ? () => _pauseActivity(activity) : null,
              icon: const Icon(Icons.pause_rounded, size: 25),
              color: Colors.orange,
            ),
            IconButton(
              tooltip: 'توقف و ثبت',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              padding: EdgeInsets.zero,
              onPressed: () => _stopActivity(activity),
              icon: const Icon(Icons.stop_rounded, size: 25),
              color: Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityControlDock(_RunningActivity activity) {
    final isRunning = activity.stopwatch.isRunning;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE4E7ED)),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'صفحه ثبت زمان',
            onPressed: () => setState(() => _selectedIndex = 0),
            icon: const Icon(Icons.home_rounded),
            color: _accentColor,
          ),
          Expanded(
            child: TextField(
              controller: activity.nameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'نام فعالیت',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF7F8FC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                activity.name = value;
                if (mounted) setState(() {});
              },
              onSubmitted: (_) => _saveActivityName(activity),
            ),
          ),
          IconButton(
            tooltip: 'ذخیره نام فعالیت',
            onPressed: () => _saveActivityName(activity),
            icon: const Icon(Icons.save_outlined),
            color: _accentColor,
          ),
          IconButton.filled(
            tooltip: isRunning ? 'مکث' : 'ادامه',
            onPressed: isRunning
                ? () => _pauseActivity(activity)
                : () => _startActivity(activity),
            icon: Icon(isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
            style: IconButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'توقف و ثبت فعالیت',
            onPressed: () => _stopActivity(activity),
            icon: const Icon(Icons.stop_circle_outlined),
            color: const Color(0xFFC62828),
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
    final current = (start ? _reportStartDate : _reportEndDate) ?? DateTime.now();
    final initial = Jalali.fromDateTime(current);
    const months = [
      'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
      'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
    ];
    var year = initial.year;
    var month = initial.month;
    var day = initial.day;

    final selected = await showDialog<Jalali>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final monthLength = Jalali(year, month, 1).monthLength;
          if (day > monthLength) day = monthLength;
          return AlertDialog(
            title: Text(start ? 'انتخاب تاریخ شروع' : 'انتخاب تاریخ پایان'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: year, isExpanded: true,
                      decoration: const InputDecoration(labelText: 'سال', border: OutlineInputBorder()),
                      items: List.generate(201, (i) => 1300 + i)
                        .map((v) => DropdownMenuItem(value: v, child: Text(_persianDigits(v.toString())))).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          year = v;
                          final length = Jalali(year, month, 1).monthLength;
                          if (day > length) day = length;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      value: month, isExpanded: true,
                      decoration: const InputDecoration(labelText: 'ماه', border: OutlineInputBorder()),
                      items: List.generate(12, (i) => i + 1)
                        .map((v) => DropdownMenuItem(value: v, child: Text(months[v - 1]))).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          month = v;
                          final length = Jalali(year, month, 1).monthLength;
                          if (day > length) day = length;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: day, isExpanded: true,
                      decoration: const InputDecoration(labelText: 'روز', border: OutlineInputBorder()),
                      items: List.generate(monthLength, (i) => i + 1)
                        .map((v) => DropdownMenuItem(value: v, child: Text(_persianDigits(v.toString())))).toList(),
                      onChanged: (v) { if (v != null) setDialogState(() => day = v); },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text(
                  _persianDigits(year.toString() + '/' + _twoDigits(month) + '/' + _twoDigits(day)),
                  style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, Jalali(year, month, day)),
                child: const Text('تأیید'),
              ),
            ],
          );
        },
      ),
    );

    if (selected == null || !mounted) return;
    final gregorian = selected.toDateTime();
    setState(() {
      if (start) {
        _reportStartDate = DateTime(gregorian.year, gregorian.month, gregorian.day);
      } else {
        _reportEndDate = DateTime(gregorian.year, gregorian.month, gregorian.day);
      }
    });
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
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'گزارش زمان فعالیت‌ها'));
  }

  Future<void> _showReportActivityPicker() async {
    final selected = Set<String>.from(_reportSelectedNames);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          title: const Text('انتخاب فعالیت‌ها'),
          content: SizedBox(
            width: double.maxFinite,
            child: _activityNames.isEmpty
                ? const Text('هنوز فعالیتی ثبت نشده است.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('انتخاب همه فعالیت‌ها'),
                        value: selected.length == _activityNames.length,
                        onChanged: (value) => refreshDialog(() {
                          if (value == true) {
                            selected.addAll(_activityNames);
                          } else {
                            selected.clear();
                          }
                        }),
                      ),
                      const Divider(height: 1),
                      ..._activityNames.map((name) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        value: selected.contains(name),
                        onChanged: (value) => refreshDialog(() {
                          if (value == true) {
                            selected.add(name);
                          } else {
                            selected.remove(name);
                          }
                        }),
                      )),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _reportSelectedNames
                    ..clear()
                    ..addAll(selected);
                });
                Navigator.pop(dialogContext);
              },
              child: const Text('اعمال انتخاب'),
            ),
          ],
        ),
      ),
    );
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
      OutlinedButton.icon(
        onPressed: _showReportActivityPicker,
        icon: const Icon(Icons.tune),
        label: const Text('انتخاب فعالیت‌ها'),
      ),
      if (_reportSelectedNames.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'فعالیت‌های انتخاب‌شده: ${_persianDigits(_reportSelectedNames.length.toString())}',
            style: const TextStyle(color: Colors.black54),
          ),
        )
      else
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('در حال نمایش گزارش همه فعالیت‌ها', style: TextStyle(color: Colors.black54)),
        ),
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
      'activityCategories': _activityCategories,
      'activityCategoryNames': _activityCategoryNames,
    });
    final path = await FilePicker.saveFile(
      dialogTitle: 'ذخیره فایل پشتیبان',
      fileName: 'timer_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(content),
    );
    if (path != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل پشتیبان ذخیره شد.')));
  }

  Future<void> _restoreData() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (picked == null || !mounted) return;
    try {
      final fileBytes = await picked.readAsBytes();
      final data = jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>;
      if (data['format'] != 'timer_main_backup' || data['version'] != 1) throw const FormatException('فایل پشتیبان معتبر نیست.');
      final names = (data['activityNames'] as List<dynamic>).cast<String>().toSet().toList();
      final saved = (data['savedActivities'] as List<dynamic>).map((e) => _SavedActivity.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final restoredCategories = Map<String, String>.from(
        (data['activityCategories'] as Map?)?.map((key, value) => MapEntry(key.toString(), value.toString())) ?? {},
      );
      final restoredCategoryNames = (data['activityCategoryNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString()).toSet().toList()..sort();
      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('بازیابی اطلاعات'),
        content: const Text('اطلاعات فعلی با فایل پشتیبان جایگزین می‌شود. ادامه می‌دهی؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بازیابی'))],
      ));
      if (yes != true || !mounted) return;
      for (final activity in _runningActivities) {
        activity.dispose();
      }
      setState(() {
        _activityNames = names..sort();
        _savedActivities = saved;
        _activityCategories = restoredCategories;
        _activityCategoryNames = restoredCategoryNames;
        _runningActivities.clear();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_namesStorageKey, _activityNames);
      await prefs.setString(_storageKey, jsonEncode(_savedActivities.map((a) => a.toJson()).toList()));
      await prefs.setString(_categoriesStorageKey, jsonEncode(_activityCategories));
      await prefs.setStringList('activity_category_names_v1', _activityCategoryNames);
      await prefs.setString(_runningActivitiesStorageKey, jsonEncode(<dynamic>[]));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بازیابی انجام شد.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در بازیابی: ' + e.toString())));
    }
  }



  Future<void> _clearRemovedChecklistData() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'checklists_v1',
      'checklist_item_font_size_v1',
      'checklist_title_font_size_v1',
      'checklist_item_font_path_v1',
      'checklist_title_font_path_v1',
      'checklist_item_font_family_v1',
      'checklist_title_font_family_v1',
    ]) {
      await prefs.remove(key);
    }
  }

  Future<void> _initializeAlarmNotifications() async {
    await _loadCountdownAlarmSettings();
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    const channel = AndroidNotificationChannel(
      'countdown_alarm_channel', 'هشدار پایان تایمر',
      description: 'هشدار صوتی هنگام پایان تایمر معکوس',
      importance: Importance.max, playSound: true, enableVibration: true,
    );
    await android?.createNotificationChannel(channel);
    await _restoreCountdowns();
    await _loadDailyReminders();
  }

  Future<void> _persistCountdowns() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_countdownsStorageKey,
        jsonEncode(_countdowns.map((item) => item.toJson()).toList()));
  }

  Future<void> _restoreCountdowns() async {    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_countdownsStorageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = decoded.map((item) =>
          _CountdownTimer.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      final now = DateTime.now();
      final expired = <_CountdownTimer>[];
      for (final item in restored) {
        if (item.running && item.endsAt != null) {          final left = item.endsAt!.difference(now).inSeconds;
          if (left <= 0) {
            item.remainingSeconds = 0;
            item.running = false;
            item.finished = true;
            item.endsAt = null;
            expired.add(item);
          } else {
            item.remainingSeconds = left;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _countdowns..clear()..addAll(restored);
        _nextCountdownId = _countdowns.isEmpty ? 1000 :
            _countdowns.map((item) => item.id).reduce((a, b) => a > b ? a : b) + 1;
      });
      for (final item in restored.where((item) => item.running)) {
        await _scheduleCountdownAlarm(item);
      }
      for (final item in expired) { await _finishCountdown(item); }
      await _persistCountdowns();
    } catch (_) {
      // Ignore damaged timer data without blocking startup.
    }
  }
  Future<void> _loadCountdownAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _countdownAlarmEnabled = prefs.getBool('countdown_alarm_enabled') ?? true;
      _countdownAlarmSound = prefs.getBool('countdown_alarm_sound') ?? true;
      _countdownAlarmVibration = prefs.getBool('countdown_alarm_vibration') ?? true;
      _customAlarmSoundPath = prefs.getString('countdown_custom_sound_path');
    });
  }

  Future<void> _pickCustomAlarmSound() async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked == null || picked.path == null) return;
    try {
      final sourcePath = picked.path!;
      final dir = await getApplicationSupportDirectory();
      final fileName = sourcePath.split(RegExp(r'[/\\]')).last;
      final saved = await File(sourcePath).copy('${dir.path}/timer_alarm_${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('countdown_custom_sound_path', saved.path);
      if (!mounted) return;
      setState(() => _customAlarmSoundPath = saved.path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صدای هشدار انتخاب شد. برای آزمایش، دکمه پخش را بزن.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره فایل صدا انجام نشد. دوباره تلاش کن.')));
    }
  }
  Future<void> _clearCustomAlarmSound() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('countdown_custom_sound_path');
    if (!mounted) return;
    setState(() => _customAlarmSoundPath = null);
  }
  Future<void> _previewCustomAlarmSound() async {
    final path = _customAlarmSoundPath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ابتدا یک فایل صدا انتخاب کن.')));
      return;
    }
    try {
      await _customAlarmPlayer.stop();
      await _customAlarmPlayer.play(DeviceFileSource(path));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پخش این فایل صدا ممکن نشد.')));
    }
  }

  Future<void> _saveCountdownAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('countdown_alarm_enabled', _countdownAlarmEnabled);
    await prefs.setBool('countdown_alarm_sound', _countdownAlarmSound);
    await prefs.setBool('countdown_alarm_vibration', _countdownAlarmVibration);
    if (!_countdownAlarmEnabled) {
      for (final item in _countdowns) { await _notifications.cancel(item.id); }
    } else {
      for (final item in _countdowns.where((item) => item.running)) {
        await _scheduleCountdownAlarm(item);
      }
    }
  }

  NotificationDetails get _alarmDetails => NotificationDetails(android:AndroidNotificationDetails(
    'countdown_alarm_channel','هشدار پایان تایمر',channelDescription:'هشدار هنگام پایان تایمر معکوس',
    importance:Importance.max,priority:Priority.max,playSound:_countdownAlarmSound,
    enableVibration:_countdownAlarmVibration,
    category:AndroidNotificationCategory.alarm,audioAttributesUsage:AudioAttributesUsage.alarm));
  Future<void> _scheduleCountdownAlarm(_CountdownTimer item) async {
    if(item.endsAt==null || !_countdownAlarmEnabled)return;
    await _notifications.zonedSchedule(item.id,'زمان تایمر به پایان رسید',item.title,
      tz.TZDateTime.from(item.endsAt!,tz.local),_alarmDetails,
      androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,payload:'countdown:'+item.id.toString());
  }
  void _tickCountdowns(){
    var changed=false;
    var completed=false;
    for(final item in _countdowns){
      if(!item.running||item.endsAt==null)continue;
      final left=item.endsAt!.difference(DateTime.now()).inSeconds;
      final next=left<=0?0:left;
      if(next!=item.remainingSeconds){item.remainingSeconds=next;changed=true;}
      if(next<=0){item.running=false;item.finished=true;item.endsAt=null;_finishCountdown(item);changed=true;completed=true;}
    }
    if(changed&&mounted)setState((){});
    if (completed) _persistCountdowns();
  }
  Future<void> _recordCountdownCompletion(_CountdownTimer item) async {
    if (item.completionLogged) return;
    final completedAt = _programNow;
    final startedAt = item.startedAt ?? completedAt.subtract(Duration(seconds: item.totalSeconds));
    final name = item.title.trim().isEmpty ? 'تایمر' : item.title.trim();
    item.completionLogged = true;
    final saved = _SavedActivity(
      name: name,
      startDate: _jalaliDate(startedAt),
      startTime: _clockTime(startedAt),
      endDate: _jalaliDate(completedAt),
      endTime: _clockTime(completedAt),
      durationSeconds: item.totalSeconds,
    );
    if (!mounted) return;
    setState(() {
      _savedActivities.insert(0, saved);
      if (!_activityNames.contains(name)) {
        _activityNames.add(name);
        _activityNames.sort();
      }
      _activityCategories.putIfAbsent(name, () => 'بدون پوشه');
    });
    await _persistActivities();
    await _persistActivityNames();
    await _persistActivityCategories();
    await _persistCountdowns();
  }

  Future<void> _loadDailyReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dailyRemindersStorageKey);
    if (raw == null) return;
    try {
      final decoded = (jsonDecode(raw) as List<dynamic>).map((item) => _DailyReminder.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      if (!mounted) return;
      setState(() { _dailyReminders..clear()..addAll(decoded); _nextDailyReminderId = _dailyReminders.isEmpty ? 850000 : _dailyReminders.map((item) => item.id).reduce((a, b) => a > b ? a : b) + 1; });
      for (final item in decoded) { await _scheduleDailyReminder(item); }
    } catch (_) { }
  }
  Future<void> _saveDailyReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyRemindersStorageKey, jsonEncode(_dailyReminders.map((item) => item.toJson()).toList()));
  }
  Future<void> _scheduleDailyReminder(_DailyReminder item) async {
    await _notifications.cancel(item.id);
    if (!item.scheduledAt.isAfter(DateTime.now())) return;
    final soundPath = item.soundPath;
    final channel = soundPath == null ? 'daily_reminder_default' : 'daily_reminder_' + item.id.toString();
    final sound = soundPath != null && File(soundPath).existsSync() ? UriAndroidNotificationSound(Uri.file(soundPath).toString()) : null;
    final details = AndroidNotificationDetails(channel, 'یادآورهای شخصی', channelDescription: 'اعلان یادآورهای ثبت‌شده', importance: Importance.max, priority: Priority.max, category: AndroidNotificationCategory.alarm, playSound: true, sound: sound, audioAttributesUsage: AudioAttributesUsage.alarm);
    await _notifications.zonedSchedule(item.id, 'یادآور', item.text, tz.TZDateTime.from(item.scheduledAt, tz.local), NotificationDetails(android: details), androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, payload: 'daily-reminder:' + item.id.toString());
  }
  Widget _buildDailyRemindersPage() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _openNewDailyReminder, icon: const Icon(Icons.add_alert), label: const Text('یادآور جدید'), style: FilledButton.styleFrom(backgroundColor: _accentColor, padding: const EdgeInsets.symmetric(vertical: 14)))),
      const SizedBox(height: 14),
      if (_dailyReminders.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Center(child: Text('هنوز یادآوری‌ای ثبت نشده است.')))
      else ..._dailyReminders.map((item) => Card(color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE8EAF0))), child: ListTile(leading: Icon(Icons.notifications_active_outlined, color: _accentColor), title: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(_jalaliDate(item.scheduledAt) + ' • ' + _clockTime(item.scheduledAt, withSeconds: false)), trailing: IconButton(tooltip: 'حذف یادآور', icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async { await _notifications.cancel(item.id); if (!mounted) return; setState(() => _dailyReminders.remove(item)); await _saveDailyReminders(); }))))
    ]);
  }
  Future<void> _openNewDailyReminder() async {
    final item = await Navigator.of(context).push<_DailyReminder>(MaterialPageRoute(builder: (_) => const _DailyReminderFormPage()));
    if (item == null || !mounted) return;
    item.id = _nextDailyReminderId++;
    setState(() => _dailyReminders.add(item));
    await _saveDailyReminders();
    await _scheduleDailyReminder(item);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('یادآور ذخیره و زمان‌بندی شد.')));
  }

  Future<void> _finishCountdown(_CountdownTimer item) async {
    await _recordCountdownCompletion(item);
    await _notifications.cancel(item.id);
    if (_countdownAlarmEnabled) {
      await _notifications.show(item.id,'پایان تایمر','زمان «'+item.title+'» به پایان رسید.',_alarmDetails,payload:'countdown:'+item.id.toString());
      final customPath = item.alarmSoundPath;
      if (_countdownAlarmSound && customPath != null && File(customPath).existsSync()) {
        try { await _customAlarmPlayer.stop(); await _customAlarmPlayer.play(DeviceFileSource(customPath)); }
        catch (_) { SystemSound.play(SystemSoundType.alert); }
      } else if (_countdownAlarmSound) { SystemSound.play(SystemSoundType.alert); }
    }
  }
  Future<void> _addCountdown() async {
    final seconds = _wheelHours * 3600 + _wheelMinutes * 60 + _wheelSeconds;
    if (seconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا یک زمان بیشتر از صفر انتخاب کن.')),
      );
      return;
    }
    setState(() => _countdowns.add(_CountdownTimer(
      id: _nextCountdownId++, title: 'تایمر ' + (_countdowns.length + 1).toString(),
      totalSeconds: seconds,
    )));
    await _persistCountdowns();
  }
  Future<void> _renameCountdown(_CountdownTimer item) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameCountdownDialog(initialName: item.title),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    setState(() => item.title = newName.trim());
    await _persistCountdowns();
    if (item.running) await _scheduleCountdownAlarm(item);
  }

  Future<void> _startCountdown(_CountdownTimer item) async {
    if(item.running||item.remainingSeconds<=0)return;
    setState(() { item.running=true; item.finished=false; item.completionLogged=false; item.startedAt ??= _programNow; item.endsAt=DateTime.now().add(Duration(seconds:item.remainingSeconds)); });
    await _persistCountdowns();
    await _scheduleCountdownAlarm(item);
  }
  Future<void> _pauseCountdown(_CountdownTimer item) async {
    if(!item.running)return;
    final remaining=item.endsAt!.difference(DateTime.now()).inSeconds;
    await _notifications.cancel(item.id);
    setState(() { item.remainingSeconds=remaining<0?0:remaining; item.running=false; item.endsAt=null; });
    await _persistCountdowns();
  }
  Future<void> _stopCountdown(_CountdownTimer item) async {
    await _notifications.cancel(item.id);
    setState(() { item.running=false; item.finished=false; item.endsAt=null; item.startedAt=null; item.completionLogged=false; item.remainingSeconds=item.totalSeconds; });
    await _persistCountdowns();
  }
  String _countdownText(int seconds){
    final h=seconds~/3600,m=(seconds%3600)~/60,s=seconds%60;
    return _persianDigits(_twoDigits(h)+':'+_twoDigits(m)+':'+_twoDigits(s));
  }
  Widget _wheelPicker(String label, int max, int selected, FixedExtentScrollController controller, ValueChanged<int> onChanged) {
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
              controller: controller,
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
            _wheelPicker('ساعت',99,_wheelHours,_hoursWheelController,(v)=>setState(()=>_wheelHours=v)),
            _wheelPicker('دقیقه',59,_wheelMinutes,_minutesWheelController,(v)=>setState(()=>_wheelMinutes=v)),
            _wheelPicker('ثانیه',59,_wheelSeconds,_secondsWheelController,(v)=>setState(()=>_wheelSeconds=v)),
          ]),
          Text(_countdownText(selectedSeconds),style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:_accentColor)),
          const SizedBox(height:12),
          SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_addCountdown,icon:const Icon(Icons.add_alarm),
            label:const Text('افزودن تایمر'),style:FilledButton.styleFrom(backgroundColor:_accentColor))),
          const SizedBox(height:14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal:12, vertical:6),
            decoration: BoxDecoration(color:const Color(0xFFF7F8FC),borderRadius:BorderRadius.circular(14)),
            child: Column(children:[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('هشدار پس از اتمام تایمر',style:TextStyle(fontWeight:FontWeight.w600)),
                subtitle: const Text('پس از صفر شدن زمان، اعلان هشدار نمایش داده شود.'),
                value:_countdownAlarmEnabled, activeColor:_accentColor,
                onChanged:(v) async { setState(()=>_countdownAlarmEnabled=v); await _saveCountdownAlarmSettings(); },
              ),
              if (_countdownAlarmEnabled) ...[
                const Divider(height:1),
                SwitchListTile(
                  contentPadding:EdgeInsets.zero, title:const Text('صدای هشدار'),
                  secondary:const Icon(Icons.volume_up_outlined),
                  value:_countdownAlarmSound, activeColor:_accentColor,
                  onChanged:(v) async { setState(()=>_countdownAlarmSound=v); await _saveCountdownAlarmSettings(); },
                ),
                if (_countdownAlarmSound) Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(_customAlarmSoundPath == null ? 'صدای پیش‌فرض گوشی' : 'فایل صدای اختصاصی انتخاب شده', style: const TextStyle(fontSize: 13))),
                      if (_customAlarmSoundPath != null) IconButton(tooltip: 'پخش آزمایشی', onPressed: _previewCustomAlarmSound, icon: const Icon(Icons.play_circle_outline)),
                    ]),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                      onPressed: _pickCustomAlarmSound,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('انتخاب زنگ از حافظه گوشی'),
                    )),
                    if (_customAlarmSoundPath != null) SizedBox(width: double.infinity, child: TextButton.icon(
                      onPressed: _clearCustomAlarmSound,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('حذف زنگ انتخاب‌شده و بازگشت به پیش‌فرض'),
                    )),
                    const Text('صدای سفارشی هنگام فعال بودن خود برنامه پخش می‌شود؛ در پس‌زمینه/بسته بودن برنامه اعلان از صدای پیش‌فرض سیستم استفاده می‌کند.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ]),
                ),
                SwitchListTile(
                  contentPadding:EdgeInsets.zero, title:const Text('لرزش هنگام هشدار'),
                  secondary:const Icon(Icons.vibration),
                  value:_countdownAlarmVibration, activeColor:_accentColor,
                  onChanged:(v) async { setState(()=>_countdownAlarmVibration=v); await _saveCountdownAlarmSettings(); },
                ),
              ],
            ]),
          ),
        ])),
      const SizedBox(height:22),
      Row(children:[const Expanded(child:Text('تایمرهای من',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold))),
        Text(_persianDigits(_countdowns.length.toString()),style:TextStyle(color:_accentColor,fontWeight:FontWeight.bold))]),
      const SizedBox(height:10),
      if(_countdowns.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('هنوز تایمری اضافه نشده است.')))
      else ..._countdowns.map(_buildCountdownCard),
    ]);
  }
  Future<void> _chooseCountdownSound(_CountdownTimer item) async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked == null || picked.path == null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final fileName = picked.path!.split(RegExp(r'[/\\]')).last;
      final saved = await File(picked.path!).copy('${dir.path}/countdown_${item.id}_${DateTime.now().millisecondsSinceEpoch}_$fileName');
      if (!mounted) return;
      setState(() => item.alarmSoundPath = saved.path);
      await _persistCountdowns();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('صدای اختصاصی این تایمر ذخیره شد.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره فایل صدا انجام نشد.')));
    }
  }
  Future<void> _previewCountdownSound(_CountdownTimer item) async {
    final path = item.alarmSoundPath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای این تایمر صدای اختصاصی انتخاب نشده است.')));
      return;
    }
    try { await _customAlarmPlayer.stop(); await _customAlarmPlayer.play(DeviceFileSource(path)); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پخش فایل صدا ممکن نشد.'))); }
  }
  Widget _buildCountdownCard(_CountdownTimer item){
    final progress=item.totalSeconds==0?0.0:(item.remainingSeconds/item.totalSeconds).clamp(0.0,1.0);
    return Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(14),
      decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE8EAF0))),
      child:Column(children:[
        Row(children:[Expanded(child:Text(item.title,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))),
          IconButton(tooltip:'تغییر نام تایمر',onPressed:()=>_renameCountdown(item),icon:const Icon(Icons.edit_outlined)),
          IconButton(tooltip:'حذف تایمر',onPressed:()async{await _notifications.cancel(item.id);if(mounted){setState(()=>_countdowns.remove(item));await _persistCountdowns();}},
            icon:const Icon(Icons.delete_outline,color:Colors.redAccent))]),
        const SizedBox(height:8),
        Card(color:const Color(0xFFF7F8FC),elevation:0,child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:6),child:Column(children:[
          Row(children:[Expanded(child:Text(item.alarmSoundPath==null?'زنگ پیش‌فرض برای این تایمر':'زنگ اختصاصی انتخاب شده',style:const TextStyle(fontSize:12))),
            IconButton(tooltip:'پخش آزمایشی زنگ',onPressed:item.alarmSoundPath==null?null:()=>_previewCountdownSound(item),icon:const Icon(Icons.play_circle_outline)),
          ]),
          SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>_chooseCountdownSound(item),icon:const Icon(Icons.music_note),label:const Text('انتخاب زنگ مخصوص این تایمر'))),
          if(item.alarmSoundPath!=null) TextButton.icon(onPressed:()async{setState(()=>item.alarmSoundPath=null);await _persistCountdowns();},icon:const Icon(Icons.delete_outline),label:const Text('حذف زنگ اختصاصی')),
        ]))),
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


  Widget _activityCard(String name) {
    final active=_runningActivities.where((a)=>a.name.trim().toLowerCase()==name.trim().toLowerCase()).firstOrNull;
    final status=active==null?'آماده شروع • مشاهده سوابق':active.stopwatch.isRunning?'● در حال اجرا':'مکث شده • برای ادامه شروع را بزن';
    const buttonSize=36.0;
    return Card(margin:const EdgeInsets.only(bottom:9),color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:Color(0xFFE8EAF0))),child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:6,vertical:2),minLeadingWidth:28,onTap:()=>_openActivityDetails(name),leading:Icon(Icons.label_outline_rounded,color:_accentColor),title:Text(name,style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text(status,style:TextStyle(color:active?.stopwatch.isRunning==true?Colors.green:Colors.black54,fontSize:12)),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
      Row(mainAxisSize:MainAxisSize.min,children:[
       SizedBox(width:buttonSize,height:buttonSize,child:IconButton(padding:EdgeInsets.zero,constraints:const BoxConstraints.tightFor(width:buttonSize,height:buttonSize),tooltip:'شروع',onPressed:active==null?()=>_startNewActivity(name):()=>_startActivity(active),icon:Icon(Icons.play_arrow_rounded,size:23,color:_accentColor))),
       SizedBox(width:buttonSize,height:buttonSize,child:IconButton(padding:EdgeInsets.zero,constraints:const BoxConstraints.tightFor(width:buttonSize,height:buttonSize),tooltip:'مکث',onPressed:active==null?null:()=>_pauseActivity(active),icon:Icon(Icons.pause_rounded,size:23,color:_accentColor))),
       SizedBox(width:buttonSize,height:buttonSize,child:IconButton(padding:EdgeInsets.zero,constraints:const BoxConstraints.tightFor(width:buttonSize,height:buttonSize),tooltip:'پایان و ثبت',onPressed:active==null?null:()=>_stopActivity(active),icon:const Icon(Icons.stop_rounded,size:23,color:Colors.redAccent))),
      ]),
      Text(_durationText(Duration(seconds:active?.stopwatch.elapsed.inSeconds??0)),textDirection:TextDirection.ltr,style:TextStyle(color:_accentColor,fontWeight:FontWeight.bold,fontSize:15)),
      PopupMenuButton<String>(tooltip:'مدیریت فعالیت',onSelected:(v){if(v=='__manual_time__'){_addManualActivityTime(name);}else if(v=='__edit_activity__'){_editActivityName(name);}else if(v=='__delete_activity__'){_deleteActivity(name);}else if(v=='__move__'){_setActivityCategory(name);}},itemBuilder:(_)=>const [PopupMenuItem(value:'__manual_time__',child:Text('ثبت زمان دستی')),PopupMenuItem(value:'__edit_activity__',child:Text('ویرایش نام فعالیت')),PopupMenuItem(value:'__delete_activity__',child:Text('حذف فعالیت',style:TextStyle(color:Colors.red))),PopupMenuDivider(),PopupMenuItem(value:'__move__',child:Text('انتقال به پوشه'))])
    ])));
  }

  Widget _buildActivitiesPage() {
    final folders=[..._activityCategoryNames];
    final visible=_openedActivityFolder==null?_activityNames.where((n)=>(_activityCategories[n]??'بدون پوشه')=='بدون پوشه').toList():_activityNames.where((n)=>(_activityCategories[n]??'بدون پوشه')==_openedActivityFolder).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      Row(children:[const Expanded(child:Text('فهرست فعالیت‌ها',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold))),FilledButton.icon(onPressed:_addActivityToCatalog,icon:const Icon(Icons.add,size:19),label:const Text('فعالیت جدید'),style:FilledButton.styleFrom(backgroundColor:_accentColor))]),
      const SizedBox(height:10),
      SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('فعالیت‌ها'),icon:Icon(Icons.list_alt)),ButtonSegment(value:true,label:Text('پوشه‌ها'),icon:Icon(Icons.folder_outlined))],selected:{_activitiesGroupedView},onSelectionChanged:(v)=>setState(()=>_activitiesGroupedView=v.first)),
      const SizedBox(height:10),
      Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:_manageActivityCategories,icon:const Icon(Icons.folder_open),label:const Text('مدیریت پوشه‌ها'))),
      if(!_activitiesGroupedView)...[
        const Text('همه فعالیت‌ها مستقل از پوشه‌ها در این فهرست نمایش داده می‌شوند.',style:TextStyle(color:Colors.black54)),
        const SizedBox(height:8),
        if(_activityNames.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('هنوز فعالیتی اضافه نکرده‌ای.'))) else ..._activityNames.map(_activityCard),
      ]else if(_openedActivityFolder!=null)...[
        Row(children:[IconButton(onPressed:()=>setState(()=>_openedActivityFolder=null),icon:const Icon(Icons.arrow_back)),Expanded(child:Text(_openedActivityFolder!,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))]),
        if(visible.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('این پوشه هنوز فعالیتی ندارد.')))else ...visible.map(_activityCard),
      ]else...[
        Card(color:Colors.white,elevation:0,child:ListTile(leading:Icon(Icons.folder_off_outlined,color:_accentColor),title:const Text('بدون پوشه'),subtitle:Text('${_activityNames.where((n)=>(_activityCategories[n]??'بدون پوشه')=='بدون پوشه').length} فعالیت'),onTap:()=>setState(()=>_openedActivityFolder='بدون پوشه'))),
        if(folders.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('هنوز پوشه‌ای برای فعالیت‌ها ساخته نشده است.')))
        else ...folders.map((folder)=>Card(color:Colors.white,elevation:0,child:ListTile(leading:Icon(Icons.folder,color:_accentColor),title:Text(folder),subtitle:Text('${_activityNames.where((n)=>(_activityCategories[n]??'بدون پوشه')==folder).length} فعالیت'),trailing:const Icon(Icons.chevron_left),onTap:()=>setState(()=>_openedActivityFolder=folder)))),
      ],
    ]);
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
}class _DailyReminderFormPage extends StatefulWidget {
  const _DailyReminderFormPage();

  @override
  State<_DailyReminderFormPage> createState() => _DailyReminderFormPageState();
}

class _DailyReminderFormPageState extends State<_DailyReminderFormPage> {
  final _text = TextEditingController();
  final _player = AudioPlayer();
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5)));
  String? _soundPath;

  @override
  void dispose() {
    _text.dispose();
    _player.dispose();
    super.dispose();
  }

  DateTime get _when => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  String _dateText(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return j.year.toString() + '/' + j.month.toString().padLeft(2, '0') + '/' + j.day.toString().padLeft(2, '0');
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(DateTime.now()) ? DateTime.now() : _date,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null && mounted) setState(() => _time = t);
  }

  Future<void> _pickSound() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null || file.path == null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final name = file.path!.split('/').last;
      final copied = await File(file.path!).copy(
        dir.path + '/reminder_sound_' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + name,
      );
      if (mounted) setState(() => _soundPath = copied.path);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره فایل زنگ انجام نشد.')));
    }
  }

  Future<void> _preview() async {
    final path = _soundPath;
    if (path == null || !File(path).existsSync()) return;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پخش زنگ ممکن نشد.')));
    }
  }

  void _save() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متن یادآور را وارد کن.')));
      return;
    }
    if (!_when.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاریخ و ساعت باید در آینده باشد.')));
      return;
    }
    Navigator.of(context).pop(_DailyReminder(id: 0, text: text, scheduledAt: _when, soundPath: _soundPath));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('یادآور جدید')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'متن یادآور',
              hintText: 'چه چیزی را می‌خواهی به خاطر بسپاری؟',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('تاریخ'),
              subtitle: Text(_dateText(_date)),
              trailing: const Icon(Icons.chevron_left),
              onTap: _pickDate,
            ),
          ),
          Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('ساعت'),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.chevron_left),
              onTap: _pickTime,
            ),
          ),
          Card(
            color: Colors.white,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('زنگ هشدار', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    _soundPath == null ? 'زنگ پیش‌فرض' : _soundPath!.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickSound,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('انتخاب زنگ از حافظه گوشی'),
                        ),
                      ),
                      if (_soundPath != null)
                        IconButton(
                          tooltip: 'پخش آزمایشی زنگ',
                          onPressed: _preview,
                          icon: const Icon(Icons.play_circle_outline),
                        ),
                    ],
                  ),
                  if (_soundPath != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _soundPath = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('بازگشت به زنگ پیش‌فرض'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('ذخیره یادآور'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }
}
