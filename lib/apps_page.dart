import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('timer_main/app_launcher');
  static const _keys = ['app_launcher_tab_1_v1', 'app_launcher_tab_2_v1'];
  late final TabController _tabs;
  final _slots = [_AppSlot(title: 'حساب شخصی'), _AppSlot(title: 'حساب کاری')];
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < 2; i++) {
      final raw = prefs.getString(_keys[i]);
      if (raw == null) continue;
      try { _slots[i] = _AppSlot.fromJson(jsonDecode(raw) as Map<String, dynamic>); } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(int i) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keys[i], jsonEncode(_slots[i].toJson()));
  }

  Future<void> _rename(int i) async {
    final controller = TextEditingController(text: _slots[i].title);
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تغییر نام تب'),
      content: TextField(controller: controller, autofocus: true, maxLength: 32,
        decoration: const InputDecoration(labelText: 'نام تب'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ذخیره')),
      ],
    ));
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _slots[i].title = name.trim());
    await _save(i);
  }

  Future<void> _choose(int i) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getLaunchableApps') ?? [];
      final apps = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        ..sort((a,b) => (a['label'] as String? ?? '').toLowerCase().compareTo((b['label'] as String? ?? '').toLowerCase()));
      if (!mounted) return;
      final selected = await showDialog<Map<String,dynamic>>(context: context,
        builder: (_) => _AppPickerDialog(apps: apps));
      if (selected == null || !mounted) return;
      setState(() {
        _slots[i]
          ..packageName = selected['packageName'] as String
          ..appName = selected['label'] as String
          ..iconBase64 = selected['icon'] as String?;
      });
      await _save(i);
    } on PlatformException catch (e) {
      _message(e.message ?? 'فهرست برنامه‌ها دریافت نشد.');
    } on MissingPluginException {
      _message('قابلیت انتخاب برنامه در این نسخه نصب نشده است.');
    }
  }

  Future<void> _clear(int i) async {
    setState(() { _slots[i]..packageName = null..appName = null..iconBase64 = null; });
    await _save(i);
  }

  Future<void> _launch(int i) async {
    final packageName = _slots[i].packageName;
    if (packageName == null || _opening) return;
    setState(() => _opening = true);
    try {
      final ok = await _channel.invokeMethod<bool>('launchApp', {'packageName': packageName});
      if (ok != true && mounted) _message('اجرای برنامه ممکن نشد؛ ممکن است حذف یا غیرفعال شده باشد.');
    } on PlatformException catch (e) {
      if (mounted) _message(e.message ?? 'اجرای برنامه با خطا روبه‌رو شد.');
    } on MissingPluginException {
      if (mounted) _message('قابلیت اجرای برنامه در این نسخه نصب نشده است.');
    } finally { if (mounted) setState(() => _opening = false); }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Widget _icon(_AppSlot slot, {double size = 64}) {
    final data = slot.iconBase64;
    if (data != null && data.isNotEmpty) {
      try { return Image.memory(Uint8List.fromList(base64Decode(data)), width: size, height: size,
        fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback(size)); } catch (_) {}
    }
    return _fallback(size);
  }

  Widget _fallback(double size) => Container(width: size, height: size,
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
    child: Icon(Icons.android_rounded, size: size * .6));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Material(color: Theme.of(context).colorScheme.surface,
        child: TabBar(controller: _tabs, tabs: [Tab(text: _slots[0].title), Tab(text: _slots[1].title)])),
      Expanded(child: TabBarView(controller: _tabs, children: List.generate(2, _buildSlot))),
    ]);
  }

  Widget _buildSlot(int i) {
    final slot = _slots[i];
    final hasApp = slot.packageName != null;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 22, 18, 28), children: [
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: () => _rename(i), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تغییر نام تب'))),
      const SizedBox(height: 24),
      Center(child: _icon(slot, size: 78)),
      const SizedBox(height: 14),
      Center(child: Text(slot.appName ?? 'هنوز برنامه‌ای انتخاب نشده است',
        textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
      if (hasApp) ...[
        const SizedBox(height: 6),
        Center(child: Text(slot.packageName!, textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 11, color: Colors.black54))),
      ],
      const SizedBox(height: 28),
      FilledButton.icon(onPressed: () => _choose(i), icon: const Icon(Icons.apps_rounded),
        label: Text(hasApp ? 'تغییر برنامه انتخاب‌شده' : 'انتخاب برنامه از گوشی')),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(onPressed: !hasApp || _opening ? null : () => _launch(i),
        icon: const Icon(Icons.open_in_new_rounded),
        label: Text(_opening ? 'در حال اجرا...' : 'اجرای ' + slot.title)),
      if (hasApp) ...[
        const SizedBox(height: 8),
        TextButton.icon(onPressed: () => _clear(i),
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          label: const Text('حذف برنامه از این تب', style: TextStyle(color: Colors.redAccent))),
      ],
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 8),
      const Text('هر تب تنظیمات مستقل دارد. می‌توانی یک برنامه را در هر دو تب انتخاب کنی یا برای هر تب برنامه متفاوتی قرار بدهی.',
        textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.7)),
    ]);
  }
}

class _AppPickerDialog extends StatefulWidget {
  final List<Map<String,dynamic>> apps;
  const _AppPickerDialog({required this.apps});
  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}
class _AppPickerDialogState extends State<_AppPickerDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.apps.where((app) {
      final q = query.trim().toLowerCase();
      return (app['label'] as String? ?? '').toLowerCase().contains(q) ||
        (app['packageName'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
    return AlertDialog(title: const Text('انتخاب برنامه'),
      content: SizedBox(width: double.maxFinite, height: MediaQuery.sizeOf(context).height * .62,
        child: Column(children: [
          TextField(autofocus: true, onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(hintText: 'جست‌وجوی نام یا شناسه برنامه',
              prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Expanded(child: filtered.isEmpty ? const Center(child: Text('برنامه‌ای پیدا نشد.')) :
            ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
              final app = filtered[i];
              Widget icon = const Icon(Icons.android, size: 34);
              final encoded = app['icon'] as String?;
              if (encoded != null && encoded.isNotEmpty) {
                try { icon = Image.memory(base64Decode(encoded), width: 38, height: 38); } catch (_) {}
              }
              return ListTile(leading: SizedBox(width: 42, height: 42, child: Center(child: icon)),
                title: Text(app['label'] as String? ?? 'برنامه بدون نام'),
                subtitle: Text(app['packageName'] as String? ?? '', textDirection: TextDirection.ltr,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, app));
            })),
        ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))]);
  }
}

class _AppSlot {
  String title;
  String? packageName;
  String? appName;
  String? iconBase64;
  _AppSlot({required this.title, this.packageName, this.appName, this.iconBase64});
  Map<String,dynamic> toJson() => {'title':title,'packageName':packageName,'appName':appName,'iconBase64':iconBase64};
  factory _AppSlot.fromJson(Map<String,dynamic> json) => _AppSlot(
    title: json['title'] as String? ?? 'تب برنامه',
    packageName: json['packageName'] as String?, appName: json['appName'] as String?,
    iconBase64: json['iconBase64'] as String?);
}
