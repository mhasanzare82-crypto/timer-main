import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:timezone/timezone.dart' as tz;

class _Reminder {
  int id; String text, repeat, date; int hour, minute; List<int> days; bool enabled; String? soundPath;
  _Reminder(this.id,this.text,this.repeat,this.date,this.hour,this.minute,this.days,this.enabled,{this.soundPath});
  Map<String,dynamic> toJson()=>{'id':id,'text':text,'repeat':repeat,'date':date,'hour':hour,'minute':minute,'days':days,'enabled':enabled,'soundPath':soundPath};
  factory _Reminder.fromJson(Map<String,dynamic> j)=>_Reminder(j['id'] as int,j['text'] as String? ?? '',j['repeat'] as String? ?? 'once',j['date'] as String? ?? '',j['hour'] as int? ?? 8,j['minute'] as int? ?? 0,(j['days'] as List? ?? []).whereType<num>().map((e)=>e.toInt()).toList(),j['enabled'] as bool? ?? true,soundPath:j['soundPath'] as String?);
}

class DailyRemindersPage extends StatefulWidget {
  const DailyRemindersPage({super.key});
  @override State<DailyRemindersPage> createState()=>_DailyRemindersPageState();
}

class _DailyRemindersPageState extends State<DailyRemindersPage> {
  static const _key='daily_reminders_v1';
  static const _zone=MethodChannel('timer_main/device_timezone');
  static const _soundChannel=MethodChannel('timer_main/reminder_sounds');
  final _plugin=FlutterLocalNotificationsPlugin();
  final List<_Reminder> _items=[];
  bool _loading=true, _ready=false;

  @override void initState(){super.initState();_init();}
  Future<void> _init() async {
    try {
      await _plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')));
      final zone=await _zone.invokeMethod<String>('getLocalTimezone');
      if(zone!=null && zone.isNotEmpty) tz.setLocalLocation(tz.getLocation(zone));
      final android=_plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel('daily_reminders_channel','یادآوری‌های روزانه',description:'اعلان متن یادآوری‌ها',importance:Importance.max));
      _ready=true;
    } catch(e){debugPrint('Reminder notification setup: $e');}
    final prefs=await SharedPreferences.getInstance();
    try { final raw=prefs.getString(_key); if(raw!=null) _items.addAll((jsonDecode(raw) as List).map((e)=>_Reminder.fromJson(Map<String,dynamic>.from(e)))); } catch(e){debugPrint('Reminder storage: $e');}
    final now=DateTime.now();
    var expiredOnce=false;
    for(var i=0;i<_items.length;i++) {
      final r=_items[i];
      if(r.enabled && r.repeat=='once') {
        final d=_date(r);
        if(d==null || !DateTime(d.year,d.month,d.day,r.hour,r.minute).isAfter(now)) {
          _items[i]=_Reminder(r.id,r.text,r.repeat,r.date,r.hour,r.minute,r.days,false);
          expiredOnce=true;
        }
      }
    }
    if(expiredOnce) await _save();
    if(mounted)setState(()=>_loading=false);
    if(_ready) for(final item in _items.where((e)=>e.enabled)) { await _schedule(item); }
  }
  Future<void> _save() async {final p=await SharedPreferences.getInstance();await p.setString(_key,jsonEncode(_items.map((e)=>e.toJson()).toList()));}
  int _nid(_Reminder r,int suffix)=>850000+r.id*10+suffix;
  String _channelId(_Reminder r)=>'daily_reminder_${r.id}_${r.soundPath==null?'default':r.soundPath!.split('/').last.replaceAll(RegExp(r'[^a-zA-Z0-9_]'),'_')}';
  Future<void> _ensureSoundChannel(_Reminder r) async {
    await _soundChannel.invokeMethod<void>('createReminderChannel',{
      'channelId':_channelId(r),'name':'یادآوری ${r.id}',
      'soundFileName':r.soundPath==null?null:r.soundPath!.split('/').last,
    });
  }
  Future<void> _deleteSoundChannel(String id) async {try{await _soundChannel.invokeMethod<void>('deleteReminderChannel',{'channelId':id});}catch(e){debugPrint('Could not delete reminder channel: $e');}}
  Future<void> _cancel(_Reminder r) async {for(var i=0;i<=7;i++){await _plugin.cancel(_nid(r,i));}}
  NotificationDetails _details(_Reminder r)=>NotificationDetails(android:AndroidNotificationDetails(_channelId(r),'یادآوری ${r.id}',importance:Importance.max,priority:Priority.max,category:AndroidNotificationCategory.reminder));
  DateTime? _date(_Reminder r){
    final p=r.date.split('/'); if(p.length!=3)return null;
    try{return Jalali(int.parse(p[0]),int.parse(p[1]),int.parse(p[2])).toDateTime();}catch(_){return null;}
  }
  DateTime _next(int h,int m,[int? weekday]){
    final now=DateTime.now();var d=DateTime(now.year,now.month,now.day,h,m);
    while(!d.isAfter(now)||(weekday!=null&&d.weekday!=weekday)){d=d.add(const Duration(days:1));d=DateTime(d.year,d.month,d.day,h,m);}return d;
  }
  Future<void> _schedule(_Reminder r) async {
    try {
    await _cancel(r);if(!_ready||!r.enabled)return;
    await _ensureSoundChannel(r);
    Future<void> add(int suffix,DateTime date,DateTimeComponents? match) async {
      await _plugin.zonedSchedule(_nid(r,suffix),'یادآوری روزانه',r.text,tz.TZDateTime.from(date,tz.local),_details(r),androidScheduleMode:AndroidScheduleMode.exactAllowWhileIdle,matchDateTimeComponents:match,payload:'daily-reminder:${r.id}');
    }
    if(r.repeat=='once'){final d=_date(r);if(d==null)return;final at=DateTime(d.year,d.month,d.day,r.hour,r.minute);if(at.isAfter(DateTime.now()))await add(0,at,null);}
    else if(r.repeat=='daily'){await add(0,_next(r.hour,r.minute),DateTimeComponents.time);}
    else {for(final day in r.days){await add(day,_next(r.hour,r.minute,day),DateTimeComponents.dayOfWeekAndTime);}}
    } catch(e) {
      debugPrint('Could not schedule daily reminder ${r.id}: $e');
      if(mounted) setState(()=>_ready=false);
    }
  }
  Future<String?> _pickReminderSound(int reminderId) async {
    try {
      final result=await FilePicker.platform.pickFiles(type:FileType.audio,allowMultiple:false);
      if(result==null)return null;
      final source=result.files.single.path;
      if(source==null){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دسترسی به فایل انتخاب‌شده ممکن نشد.')));return null;}
      final support=await getApplicationSupportDirectory();
      final directory=Directory('${support.path}/reminder_sounds');
      await directory.create(recursive:true);
      final extension=source.contains('.')?source.substring(source.lastIndexOf('.')):'.audio';
      final safeExtension=RegExp(r'^\\.[a-zA-Z0-9]{1,8}
    final text=TextEditingController(text:old?.text??'');
    final draftId=old?.id??(DateTime.now().microsecondsSinceEpoch%10000000);
    var soundPath=old?.soundPath;
    final today=Jalali.fromDateTime(DateTime.now());var date=old?.date??'${today.year}/${today.month.toString().padLeft(2,'0')}/${today.day.toString().padLeft(2,'0')}';
    var repeat=old?.repeat??'once',hour=old?.hour??TimeOfDay.now().hour,minute=old?.minute??TimeOfDay.now().minute;
    final days=<int>{...(old?.days??[])};
    final result=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:Text(old==null?'یادآوری جدید':'ویرایش یادآوری'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(controller:text,minLines:3,maxLines:5,decoration:const InputDecoration(labelText:'متن یادآوری',border:OutlineInputBorder())),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:()async{final selected=await _pickReminderSound(draftId);if(selected!=null)refresh(()=>soundPath=selected);},icon:const Icon(Icons.music_note),label:Text(soundPath==null?'انتخاب زنگ اختصاصی':soundPath!.split('/').last,maxLines:1,overflow:TextOverflow.ellipsis))),
          if(soundPath!=null)IconButton(tooltip:'استفاده از زنگ پیش‌فرض',onPressed:()=>refresh(()=>soundPath=null),icon:const Icon(Icons.close)),
        ]),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(value:repeat,decoration:const InputDecoration(labelText:'تکرار'),items:const [DropdownMenuItem(value:'once',child:Text('یک‌بار')),DropdownMenuItem(value:'daily',child:Text('هر روز')),DropdownMenuItem(value:'weekly',child:Text('روزهای هفته'))],onChanged:(v)=>refresh(()=>repeat=v??repeat)),
        if(repeat=='once') TextFormField(initialValue:date,decoration:const InputDecoration(labelText:'تاریخ شمسی (سال/ماه/روز)'),onChanged:(v)=>date=v),
        if(repeat=='weekly') Wrap(spacing:4,children:List.generate(7,(i)=>FilterChip(label:Text(['دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'][i]),selected:days.contains(i+1),onSelected:(v)=>refresh(()=>v?days.add(i+1):days.remove(i+1))))),
        ListTile(contentPadding:EdgeInsets.zero,title:Text('ساعت ${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}'),leading:const Icon(Icons.access_time),onTap:()async{final t=await showTimePicker(context:ctx,initialTime:TimeOfDay(hour:hour,minute:minute));if(t!=null)refresh(() { hour=t.hour; minute=t.minute; });}),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),FilledButton(onPressed:()=>Navigator.pop(ctx,text.text.trim().isNotEmpty&&(repeat!='weekly'||days.isNotEmpty)),child:const Text('ذخیره'))],
    )));
    final value=text.text.trim();text.dispose();if(result!=true||!mounted)return;
    if(repeat=='once'){
      final d=_date(_Reminder(0,'','once',date,0,0,[],true));
      if(d==null || !DateTime(d.year,d.month,d.day,hour,minute).isAfter(DateTime.now())) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تاریخ و ساعت باید در آینده باشد و تاریخ شمسی معتبر وارد شود.')));
        return;
      }
    }
    final id=draftId;
    final previousChannel=old==null?null:_channelId(old);
    final r=_Reminder(id,value,repeat,date,hour,minute,days.toList()..sort(),old?.enabled??true,soundPath:soundPath);
    final i=_items.indexWhere((e)=>e.id==id);setState(()=>i<0?_items.add(r):_items[i]=r);await _save();await _schedule(r);
    if(old!=null && previousChannel!=_channelId(r)) await _deleteSoundChannel(previousChannel!);
    if(old?.soundPath!=null && old!.soundPath!=soundPath) { try { await File(old.soundPath!).delete(); } catch (_) {} }
  }
  Future<void> _toggle(_Reminder r,bool v)async{final i=_items.indexOf(r);if(i<0)return;final n=_Reminder(r.id,r.text,r.repeat,r.date,r.hour,r.minute,r.days,v,soundPath:r.soundPath);setState(()=>_items[i]=n);await _save();await _schedule(n);}
  Future<void> _delete(_Reminder r)async{await _cancel(r);await _deleteSoundChannel(_channelId(r));if(r.soundPath!=null){try{await File(r.soundPath!).delete();}catch(_){}}setState(()=>_items.remove(r));await _save();}
  String _repeat(_Reminder r){if(r.repeat=='daily')return 'هر روز';if(r.repeat=='weekly'){const n=['','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'];return r.days.map((d)=>n[d]).join('، ');}return 'یک‌بار • ${r.date}';}
  @override Widget build(BuildContext context)=>Scaffold(
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add_alert),label:const Text('یادآوری جدید')),
    body:_loading?const Center(child:CircularProgressIndicator()):_items.isEmpty?const Center(child:Text('هنوز یادآوری‌ای ثبت نکرده‌ای.')):ListView(padding:const EdgeInsets.fromLTRB(12,12,12,90),children:[
      if(!_ready)const Text('مجوز اعلان و زمان‌بندی دقیق را در تنظیمات گوشی بررسی کن.',style:TextStyle(color:Colors.red)),
      ..._items.map((r)=>Card(child:ListTile(isThreeLine:true,title:Text(r.text,maxLines:4,overflow:TextOverflow.ellipsis),subtitle:Text('${r.hour.toString().padLeft(2,'0')}:${r.minute.toString().padLeft(2,'0')} • ${_repeat(r)}'),leading:Switch(value:r.enabled,onChanged:(v)=>_toggle(r,v)),trailing:PopupMenuButton<String>(onSelected:(v)=>v=='edit'?_edit(r):_delete(r),itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('ویرایش')),PopupMenuItem(value:'delete',child:Text('حذف'))])))),
    ]),
  );
}
).hasMatch(extension)?extension:'.audio';
      final fileName='reminder_${reminderId}_${DateTime.now().microsecondsSinceEpoch}$safeExtension';
      final destination='${directory.path}/$fileName';
      await File(source).copy(destination);
      return destination;
    } catch(e) {
      debugPrint('Could not select reminder sound: $e');
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('انتخاب یا ذخیره فایل صوتی انجام نشد.')));
      return null;
    }
  }

  Future<void> _edit([_Reminder? old]) async {
    final text=TextEditingController(text:old?.text??'');
    final draftId=old?.id??(DateTime.now().microsecondsSinceEpoch%10000000);
    var soundPath=old?.soundPath;
    final today=Jalali.fromDateTime(DateTime.now());var date=old?.date??'${today.year}/${today.month.toString().padLeft(2,'0')}/${today.day.toString().padLeft(2,'0')}';
    var repeat=old?.repeat??'once',hour=old?.hour??TimeOfDay.now().hour,minute=old?.minute??TimeOfDay.now().minute;
    final days=<int>{...(old?.days??[])};
    final result=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:Text(old==null?'یادآوری جدید':'ویرایش یادآوری'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(controller:text,minLines:3,maxLines:5,decoration:const InputDecoration(labelText:'متن یادآوری',border:OutlineInputBorder())),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:()async{final selected=await _pickReminderSound(draftId);if(selected!=null)refresh(()=>soundPath=selected);},icon:const Icon(Icons.music_note),label:Text(soundPath==null?'انتخاب زنگ اختصاصی':soundPath!.split('/').last,maxLines:1,overflow:TextOverflow.ellipsis))),
          if(soundPath!=null)IconButton(tooltip:'استفاده از زنگ پیش‌فرض',onPressed:()=>refresh(()=>soundPath=null),icon:const Icon(Icons.close)),
        ]),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(value:repeat,decoration:const InputDecoration(labelText:'تکرار'),items:const [DropdownMenuItem(value:'once',child:Text('یک‌بار')),DropdownMenuItem(value:'daily',child:Text('هر روز')),DropdownMenuItem(value:'weekly',child:Text('روزهای هفته'))],onChanged:(v)=>refresh(()=>repeat=v??repeat)),
        if(repeat=='once') TextFormField(initialValue:date,decoration:const InputDecoration(labelText:'تاریخ شمسی (سال/ماه/روز)'),onChanged:(v)=>date=v),
        if(repeat=='weekly') Wrap(spacing:4,children:List.generate(7,(i)=>FilterChip(label:Text(['دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'][i]),selected:days.contains(i+1),onSelected:(v)=>refresh(()=>v?days.add(i+1):days.remove(i+1))))),
        ListTile(contentPadding:EdgeInsets.zero,title:Text('ساعت ${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}'),leading:const Icon(Icons.access_time),onTap:()async{final t=await showTimePicker(context:ctx,initialTime:TimeOfDay(hour:hour,minute:minute));if(t!=null)refresh(() { hour=t.hour; minute=t.minute; });}),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('لغو')),FilledButton(onPressed:()=>Navigator.pop(ctx,text.text.trim().isNotEmpty&&(repeat!='weekly'||days.isNotEmpty)),child:const Text('ذخیره'))],
    )));
    final value=text.text.trim();text.dispose();if(result!=true||!mounted)return;
    if(repeat=='once'){
      final d=_date(_Reminder(0,'','once',date,0,0,[],true));
      if(d==null || !DateTime(d.year,d.month,d.day,hour,minute).isAfter(DateTime.now())) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تاریخ و ساعت باید در آینده باشد و تاریخ شمسی معتبر وارد شود.')));
        return;
      }
    }
    final id=draftId;
    final previousChannel=old==null?null:_channelId(old);
    final r=_Reminder(id,value,repeat,date,hour,minute,days.toList()..sort(),old?.enabled??true,soundPath:soundPath);
    final i=_items.indexWhere((e)=>e.id==id);setState(()=>i<0?_items.add(r):_items[i]=r);await _save();await _schedule(r);
    if(old!=null && previousChannel!=_channelId(r)) await _deleteSoundChannel(previousChannel!);
    if(old?.soundPath!=null && old!.soundPath!=soundPath) { try { await File(old.soundPath!).delete(); } catch (_) {} }
  }
  Future<void> _toggle(_Reminder r,bool v)async{final i=_items.indexOf(r);if(i<0)return;final n=_Reminder(r.id,r.text,r.repeat,r.date,r.hour,r.minute,r.days,v);setState(()=>_items[i]=n);await _save();await _schedule(n);}
  Future<void> _delete(_Reminder r)async{await _cancel(r);await _deleteSoundChannel(_channelId(r));if(r.soundPath!=null){try{await File(r.soundPath!).delete();}catch(_){}}setState(()=>_items.remove(r));await _save();}
  String _repeat(_Reminder r){if(r.repeat=='daily')return 'هر روز';if(r.repeat=='weekly'){const n=['','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه','شنبه','یکشنبه'];return r.days.map((d)=>n[d]).join('، ');}return 'یک‌بار • ${r.date}';}
  @override Widget build(BuildContext context)=>Scaffold(
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add_alert),label:const Text('یادآوری جدید')),
    body:_loading?const Center(child:CircularProgressIndicator()):_items.isEmpty?const Center(child:Text('هنوز یادآوری‌ای ثبت نکرده‌ای.')):ListView(padding:const EdgeInsets.fromLTRB(12,12,12,90),children:[
      if(!_ready)const Text('مجوز اعلان و زمان‌بندی دقیق را در تنظیمات گوشی بررسی کن.',style:TextStyle(color:Colors.red)),
      ..._items.map((r)=>Card(child:ListTile(isThreeLine:true,title:Text(r.text,maxLines:4,overflow:TextOverflow.ellipsis),subtitle:Text('${r.hour.toString().padLeft(2,'0')}:${r.minute.toString().padLeft(2,'0')} • ${_repeat(r)}'),leading:Switch(value:r.enabled,onChanged:(v)=>_toggle(r,v)),trailing:PopupMenuButton<String>(onSelected:(v)=>v=='edit'?_edit(r):_delete(r),itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('ویرایش')),PopupMenuItem(value:'delete',child:Text('حذف'))])))),
    ]),
  );
}
