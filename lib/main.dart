import 'package:flutter/material.dart';

void main() {
  runApp(const TimerApp());
}

class TimerApp extends StatelessWidget {
  const TimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF356AE6);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مدیریت زمان',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFFF7F8FC),
          elevation: 0,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<_TabInfo> _tabs = [
    _TabInfo(
      title: 'ثبت زمان',
      icon: Icons.add_circle_outline_rounded,
      description: 'در این بخش می‌توانی زمان فعالیت‌هایت را ثبت کنی.',
    ),
    _TabInfo(
      title: 'فعالیت‌ها',
      icon: Icons.checklist_rounded,
      description: 'فهرست فعالیت‌هایت در این قسمت نمایش داده می‌شود.',
    ),
    _TabInfo(
      title: 'گزارش‌گیری',
      icon: Icons.bar_chart_rounded,
      description: 'گزارش زمان‌های ثبت‌شده را در این بخش خواهی دید.',
    ),
    _TabInfo(
      title: 'تایمر معکوس',
      icon: Icons.hourglass_bottom_rounded,
      description: 'ابزار تایمر معکوس در این قسمت قرار می‌گیرد.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentTab.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _PlaceholderPage(
            icon: Icons.add_circle_outline_rounded,
            title: 'ثبت زمان',
            description: 'در این بخش می‌توانی زمان فعالیت‌هایت را ثبت کنی.',
          ),
          _PlaceholderPage(
            icon: Icons.checklist_rounded,
            title: 'فعالیت‌ها',
            description: 'فهرست فعالیت‌هایت در این قسمت نمایش داده می‌شود.',
          ),
          _PlaceholderPage(
            icon: Icons.bar_chart_rounded,
            title: 'گزارش‌گیری',
            description: 'گزارش زمان‌های ثبت‌شده را در این بخش خواهی دید.',
          ),
          _PlaceholderPage(
            icon: Icons.hourglass_bottom_rounded,
            title: 'تایمر معکوس',
            description: 'ابزار تایمر معکوس در این قسمت قرار می‌گیرد.',
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
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
}

class _TabInfo {
  final String title;
  final IconData icon;
  final String description;

  const _TabInfo({
    required this.title,
    required this.icon,
    required this.description,
  });
}

class _PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                icon,
                size: 42,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.7,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
