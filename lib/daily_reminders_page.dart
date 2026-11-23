import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:timezone/timezone.dart' as tz;

class _Reminder {
  final int id; final String text, repeat, date; final int hour, minute; final List<int> days; final bool enabled; final String? soundPath, soundName;
  const _Reminder({required this.id,required this.text,required this.repeat,required this.date,required this.hour,required this.minute,required this.days,required this.enabled,this.soundPath,this.soundName});
  Map<String,dynamic> toJson()=>{'id':id,'text':text,'repeat':repeat,'date':date,'hour':hour,'minute':minute,'days':days,'enabled':enabled,'soundPath':soundPath,'soundName':soundName};
  factory _Reminder.fromJson(Map<String,dynamic> j)=>_Reminder(id:(j['id'] as num?)?.toInt()??DateTime.now().millisecondsSinceEpoch%10000000,text:j['text'] as String? ?? '',repeat:j['repeat'] as String? ?? 'once',date:j['date'] as String? ?? '',hour:(j['hour'] as num?)?.toInt()??8,minute:(j['minute'] as num?)?.toInt()??0,days:(j['days'] as List? ?? []).whereType<num>().map((e)=>e.toInt()).toList(),enabled:j['enabled'] as bool? ?? true,soundPath:j['soundPath'] as String?,soundName:j['soundName'] as String?);
}
class _ReminderDraft {
  final String text, repeat, date; final int hour, minute; final List<int> days; final String? soundPath, soundName, soundSourcePath;
  const _ReminderDraft(this.text,this.repeat,this.date,this.hour,this.minute,this.days,this.soundPath,this.soundName,this.soundSourcePath);
}
class _ReminderEditor extends StatefulWidget {
  final _Reminder? original; final String initialDate;
  const _ReminderEditor({required this.original,required this.initialDate});
  @override State<_ReminderEditor> createState()=>_ReminderEditorState();
}
class _ReminderEditorState extends State<_ReminderEditor> {
  late final TextEditingController _text,_date;
  late String _repeat; late int _hour,_minute; late Set<int> _days; String? _soundPath,_soundName,_soundSourcePath;
  static const _dayNames=['دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'];
  @override void initState(){super.initState();final r=widget.original;_text=TextEditingController(text:r?.text??'');_date=TextEditingController(text:r?.date??widget.initialDate);_repeat=r?.repeat??'once';_hour=r?.hour??TimeOfDay.now().hour;_minute=r?.minute??TimeOfDay.now().minute;_days={...?r?.days};_soundPath=r?.soundPath;_soundName=r?.soundName;}
  @override void dispose(){_text.dispose();_date.dispose();super.dispose();}
  Future<void> _pickTime()async{final t=await showTimePicker(context:context,initialTime:TimeOfDay(hour:_hour,minute:_minute));if(!mounted||t==null)return;setState((){_hour=t.hour;_minute=t.minute;});}
  Future<void> _pickSound()async{try{final f=await FilePicker.platform.pickFiles(type:FileType.audio,allowMultiple:false);if(!mounted||f==null||f.files.isEmpty)return;final picked=f.files.single;if(picked.path==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دسترسی به فایل صوتی ممکن نیست.')));return;}setState((){_soundSourcePath=picked.path;_soundName=picked.name;});}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('انتخاب فایل ناموفق بود: $e')));}}
  void _removeSound()=>setState((){_soundPath=null;_soundName=null;_soundSourcePath=null;});
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.original==null?'یادآوری جدید':'ویرایش یادآوری'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(controller:_text,minLines:3,maxLines:5,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'متن یادآوری',border:OutlineInputBorder())),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(key:ValueKey(_repeat),value:_repeat,decoration:const InputDecoration(labelText:'تکرار'),items:const [DropdownMenuItem(value:'once',child:Text('یک‌بار')),DropdownMenuItem(value:'daily',child:Text('هر روز')),DropdownMenuItem(value:'weekly',child:Text('روزهای هفته'))],onChanged:(v){if(v!=null)setState(()=>_repeat=v);}),
      Visibility(visible:_repeat=='once',maintainState:true,child:TextField(controller:_date,decoration:const InputDecoration(labelText:'تاریخ شمسی (سال/ماه/روز)'))),
      Visibility(visible:_repeat=='weekly',maintainState:true,child:Wrap(spacing:4,children:List.generate(7,(i)=>FilterChip(label:Text(_dayNames[i]),selected:_days.contains(i+1),onSelected:(v)=>setState(()=>v?_days.add(i+1):_days.remove(i+1)))))),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.access_time),title:Text('ساعت ${_hour.toString().padLeft(2,'0')}:${_minute.toString().padLeft(2,'0')}'),onTap:_pickTime),
      const Divider(height:20),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.music_note),title:const Text('زنگ اختصاصی یادآور'),subtitle:Text(_soundName??'صدای پیش‌فرض گوشی'),trailing:IconButton(onPressed:_pickSound,icon:const Icon(Icons.folder_open),tooltip:'انتخاب فایل صوتی')),
      if(_soundName!=null)Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:_removeSound,icon:const Icon(Icons.delete_outline),label:const Text('حذف زنگ اختصاصی'))),
    ])),
    actions:[TextButton(onPressed:()=>Navigator.of(context).pop(),child:const Text('لغو')),FilledButton(onPressed:_text.text.trim().isNotEmpty&&(_repeat!='weekly'||_days.isNotEmpty)?()=>Navigator.of(context).pop(_ReminderDraft(_text.text.trim(),_repeat,_date.text.trim(),_hour,_minute,_days.toList()..sort(),_soundPath,_soundName,_soundSourcePath)):null,child:const Text('ذخیره'))],
  );
}
class DailyRemindersPage extends StatefulWidget {
  const DailyRemindersPage({super.key});
  @override State<DailyRemindersPage> createState()=>_DailyRemindersPageState();
}
class _DailyRemindersPageState extends State<DailyRemindersPage> {
  static const _key='daily_reminders_v1'; static const _zone=MethodChannel('timer_main/device_timezone'); static const _alarmChannel=MethodChannel('timer_main/daily_reminder_alarm');
  final _plugin=FlutterLocalNotificationsPlugin();final List<_Reminder> _items=[];
  bool _loading=true,_ready=false,_busy=false;
  @override void initState(){super.initState();_init();}
  Future<void> _init()async{
    try{await _plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')));final zone=await _zone.invokeMethod<String>('getLocalTimezone');if(zone!=null&&zone.isNotEmpty)tz.setLocalLocation(tz.getLocation(zone));final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();await android?.createNotificationChannel(const AndroidNotificationChannel('daily_reminders_channel_v2','یادآوری‌های روزانه',description:'اعلان بی‌صدا؛ زنگ توسط سرویس سیستم پخش می‌شود',importance:Importance.max));try{await android?.requestNotificationsPermission();}catch(e){debugPrint('Notification permission request skipped: $e');}try{await android?.requestExactAlarmsPermission();}catch(e){debugPrint('Exact alarm permission request skipped: $e');}_ready=true;}catch(e,st){debugPrint('Reminder notification init error: $e');debugPrintStack(stackTrace:st);}
    try{final prefs=await SharedPreferences.getInstance();final raw=prefs.getString(_key);if(raw!=null){final parsed=jsonDecode(raw);if(parsed is List)_items.addAll(parsed.whereType<Map>().map((x)=>_Reminder.fromJson(Map<String,dynamic>.from(x))));}}catch(e,st){debugPrint('Reminder load error: $e');debugPrintStack(stackTrace:st);}
    final now=DateTime.now();var expired=false;for(var i=0;i<_items.length;i++){final r=_items[i];if(r.enabled&&r.repeat=='once'){final d=_date(r);if(d==null||!DateTime(d.year,d.month,d.day,r.hour,r.minute).isAfter(now)){_items[i]=_copy(r,enabled:false);expired=true;}}}
    if(expired)await _persist(List.of(_items));if(!mounted)return;setState(()=>_loading=false);if(_ready){await _syncNative(_items);for(final r in List<_Reminder>.of(_items).where((e)=>e.enabled)){await _schedule(r);}}
  }
  Future<bool> _persist(List<_Reminder> snapshot)async{try{final prefs=await SharedPreferences.getInstance();return await prefs.setString(_key,jsonEncode(snapshot.map((r)=>r.toJson()).toList()));}catch(e,st){debugPrint('Reminder persistence error: $e');debugPrintStack(stackTrace:st);return false;}}
  _Reminder _copy(_Reminder r,{bool? enabled})=>_Reminder(id:r.id,text:r.text,repeat:r.repeat,date:r.date,hour:r.hour,minute:r.minute,days:List<int>.of(r.days),enabled:enabled??r.enabled,soundPath:r.soundPath,soundName:r.soundName);
  void _snack(String s){if(!mounted)return;ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content:Text(s)));}
  int _nid(_Reminder r,int suffix)=>850000+r.id*10+suffix;
  Future<void> _cancel(_Reminder r)async{for(var n=0;n<=7;n++){try{await _plugin.cancel(_nid(r,n));}catch(e){debugPrint('Reminder cancel error: $e');}}}
  NotificationDetails get _details=>const NotificationDetails(android:AndroidNotificationDetails('daily_reminders_channel_v2','یادآوری‌های روزانه',importance:Importance.max,priority:Priority.max,category:AndroidNotificationCategory.reminder,playSound:false));
  DateTime? _date(_Reminder r){final p=r.date.split('/');if(p.length!=3)return null;try{return Jalali(int.parse(p[0]),int.parse(p[1]),int.parse(p[2])).toDateTime();}catch(_){return null;}}
  DateTime _next(int h,int m,[int? weekday]){final now=DateTime.now();var d=DateTime(now.year,now.month,now.day,h,m);while(!d.isAfter(now)||(weekday!=null&&d.weekday!=weekday)){final n=d.add(const Duration(days:1));d=DateTime(n.year,n.month,n.day,h,m);}return d;}
  Future<bool> _syncNative(List<_Reminder> reminders)async{try{final payload=reminders.map((r){int? triggerAtMillis;if(r.repeat=='once'){final date=_date(r);if(date!=null)triggerAtMillis=DateTime(date.year,date.month,date.day,r.hour,r.minute).millisecondsSinceEpoch;}return {'id':r.id,'text':r.text,'repeat':r.repeat,'hour':r.hour,'minute':r.minute,'days':r.days,'enabled':r.enabled,'soundPath':r.soundPath,'triggerAtMillis':triggerAtMillis};}).toList();await _alarmChannel.invokeMethod<void>('syncReminders',{'reminders':jsonEncode(payload)});return true;}catch(e,st){debugPrint('Native reminder sync error: $e');debugPrintStack(stackTrace:st);return false;}}
  Future<bool> _schedule(_Reminder r)async{try{await _cancel(r);if(!_ready||!r.enabled)return _ready;Future<void> add(int suffix,DateTime when,DateTimeComponents? match)async{await _plugin.zonedSchedule(_nid(r,suffix),'یادآوری روزانه',r.text,tz.TZDateTime.from(when,tz.local),_details,androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,matchDateTimeComponents:match,payload:'daily-reminder:${r.id}');}
    if(r.repeat=='once'){final d=_date(r);if(d==null)return false;final at=DateTime(d.year,d.month,d.day,r.hour,r.minute);if(at.isAfter(DateTime.now()))await add(0,at,null);}else if(r.repeat=='daily'){await add(0,_next(r.hour,r.minute),DateTimeComponents.time);}else{for(final day in r.days){await add(day,_next(r.hour,r.minute,day),DateTimeComponents.dayOfWeekAndTime);}}return true;
  }catch(e,st){debugPrint('Reminder scheduling error id=${r.id}: $e');debugPrintStack(stackTrace:st);return false;}}
  Future<void> _edit([_Reminder? old])async{if(_busy||_loading)return;final j=Jalali.fromDateTime(DateTime.now());final initial='${j.year}/${j.month.toString().padLeft(2,'0')}/${j.day.toString().padLeft(2,'0')}';final draft=await showDialog<_ReminderDraft>(context:context,barrierDismissible:false,builder:(_)=>_ReminderEditor(original:old,initialDate:initial));if(draft==null||!mounted)return;
    if(draft.repeat=='once'){final p=draft.date.split('/');DateTime? date;if(p.length==3){try{date=Jalali(int.parse(p[0]),int.parse(p[1]),int.parse(p[2])).toDateTime();}catch(_){}}if(date==null||!DateTime(date.year,date.month,date.day,draft.hour,draft.minute).isAfter(DateTime.now())){_snack('تاریخ شمسی معتبر و زمان آینده وارد کن.');return;}}
    if(draft.repeat=='weekly'&&draft.days.isEmpty){_snack('حداقل یک روز هفته انتخاب کن.');return;}
    _busy=true;try{late final int id;if(old!=null){id=old.id;}else{var candidate=DateTime.now().microsecondsSinceEpoch%10000000;while(_items.any((e)=>e.id==candidate)){candidate=(candidate+1)%10000000;}id=candidate;}
      var soundPath=draft.soundPath;final soundName=draft.soundName;if(draft.soundSourcePath!=null){final source=File(draft.soundSourcePath!);if(!await source.exists()){_snack('فایل صوتی انتخاب‌شده در دسترس نیست؛ دوباره انتخاب کن.');return;}final support=await getApplicationSupportDirectory();final dir=Directory('${support.path}/daily_reminder_sounds');await dir.create(recursive:true);final safeName=(soundName??'reminder_audio').replaceAll(RegExp(r'[^\w. -]'),'_');final target=File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName');await source.copy(target.path);soundPath=target.path;}
      final saved=_Reminder(id:id,text:draft.text,repeat:draft.repeat,date:draft.date,hour:draft.hour,minute:draft.minute,days:List<int>.of(draft.days),enabled:old?.enabled??true,soundPath:soundPath,soundName:soundName);
      final proposed=List<_Reminder>.of(_items);final idx=proposed.indexWhere((e)=>e.id==saved.id);if(idx<0){proposed.add(saved);}else{proposed[idx]=saved;}
      // Commit storage first; only update the visible state if storage succeeds.
      if(!await _persist(proposed)){_snack('ذخیره ناموفق بود؛ داده قبلی حفظ شد.');return;}
      if(!mounted)return;setState(()=>_items..clear()..addAll(proposed));if(!await _syncNative(proposed))_snack('ذخیره شد اما زمان‌بندی زنگ سیستم انجام نشد.');if(!await _schedule(saved))_snack('یادآور ذخیره شد، ولی اعلان متنی تنظیم نشد. مجوز اعلان را بررسی کن.');
    }finally{_busy=false;}}
  Future<void> _toggle(_Reminder r,bool value)async{if(_busy)return;final i=_items.indexWhere((e)=>e.id==r.id);if(i<0)return;_busy=true;try{final changed=_copy(r,enabled:value);final proposed=List<_Reminder>.of(_items)..[i]=changed;if(!await _persist(proposed)){_snack('تغییر ذخیره نشد؛ وضعیت قبلی حفظ شد.');return;}if(!mounted)return;setState(()=>_items..clear()..addAll(proposed));final nativeOk=await _syncNative(proposed);final notifyOk=await _schedule(changed);if(!nativeOk){final rollback=List<_Reminder>.of(_items)..[i]=r;await _persist(rollback);if(mounted)setState(()=>_items..clear()..addAll(rollback));await _syncNative(rollback);await _schedule(r);_snack('تغییر فعال‌سازی ناموفق بود؛ وضعیت قبلی برگشت. مجوز هشدار دقیق را بررسی کن.');}else if(!notifyOk){_snack('زنگ فعال است، اما اعلان متنی زمان‌بندی نشد.');}}finally{_busy=false;}}
  Future<void> _delete(_Reminder r)async{if(_busy)return;_busy=true;try{final proposed=List<_Reminder>.of(_items)..removeWhere((e)=>e.id==r.id);if(!await _persist(proposed)){_snack('حذف ذخیره نشد؛ یادآور حفظ شد.');return;}if(!mounted)return;setState(()=>_items..clear()..addAll(proposed));await _cancel(r);if(!await _syncNative(proposed))_snack('یادآور حذف شد اما لغو زنگ native کامل نشد.');}finally{_busy=false;}}
  String _repeat(_Reminder r){if(r.repeat=='daily')return 'هر روز';if(r.repeat=='weekly'){const names=['','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'];return r.days.where((d)=>d>0&&d<8).map((d)=>names[d]).join('، ');}return 'یک‌بار • ${r.date}';}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _loading ? null : () => _edit(),
        icon: const Icon(Icons.add_alert),
        label: const Text('یادآوری جدید'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('هنوز یادآوری‌ای ثبت نکرده‌ای.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  children: [
                    if (!_ready)
                      const Text(
                        'مجوز اعلان و زمان‌بندی دقیق را در تنظیمات گوشی بررسی کن.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ..._items.map((r) => Card(
                          child: ListTile(
                            isThreeLine: true,
                            title: Text(r.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')} • ${_repeat(r)}',
                            ),
                            leading: Switch(
                              value: r.enabled,
                              onChanged: _busy ? null : (v) => _toggle(r, v),
                            ),
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (v) => v == 'edit' ? _edit(r) : _delete(r),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                PopupMenuItem(value: 'delete', child: Text('حذف')),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
    );
  }
}
