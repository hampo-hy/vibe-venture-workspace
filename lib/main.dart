import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const YonggongiApp());
}

// ── 브랜드 색상 ──────────────────────────────────
class AppColors {
  static const navy    = Color(0xFF131755); // 짙은 네이비
  static const blue    = Color(0xFF005799); // 메인 파랑
  static const surface = Color(0xFFF4F6FB); // 배경
  static const white   = Colors.white;
}

class NeisApiConfig {
  // dart-define(실행 시 넣는 값)으로 NEIS 인증키와 학교 코드를 바꿀 수 있어요.
  static const apiKey = String.fromEnvironment('NEIS_API_KEY', defaultValue: '');
  static const officeCode = String.fromEnvironment('NEIS_OFFICE_CODE', defaultValue: 'D10');
  static const schoolCode = String.fromEnvironment('NEIS_SCHOOL_CODE', defaultValue: '7200537');
  static const grade = String.fromEnvironment('NEIS_GRADE', defaultValue: '2');
  static const className = String.fromEnvironment('NEIS_CLASS_NM', defaultValue: '1');

  static bool get hasApiKey => apiKey.isNotEmpty;
}

class NeisApiService {
  static String _formatYmd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static List<dynamic> _extractRows(Map<String, dynamic> json, String rootKey) {
    final root = json[rootKey];
    if (root is! List || root.length < 2) return [];
    final rowContainer = root[1];
    if (rowContainer is! Map<String, dynamic>) return [];
    final rows = rowContainer['row'];
    if (rows is! List) return [];
    return rows;
  }

  static Future<List<String>> fetchTimetable(DateTime date) async {
    if (!NeisApiConfig.hasApiKey) {
      throw Exception('NEIS_API_KEY가 비어 있어요. 발급받은 키를 연결해 주세요.');
    }

    final targetYmd = _formatYmd(date);
    final uri = Uri.https('open.neis.go.kr', '/hub/hisTimetable', {
      'KEY': NeisApiConfig.apiKey,
      'Type': 'json',
      'ATPT_OFCDC_SC_CODE': NeisApiConfig.officeCode,
      'SD_SCHUL_CODE': NeisApiConfig.schoolCode,
      'GRADE': NeisApiConfig.grade,
      'CLASS_NM': NeisApiConfig.className,
      'ALL_TI_YMD': targetYmd,
      'CACHE_BUST': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('시간표 조회에 실패했어요 (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = _extractRows(decoded, 'hisTimetable');
    final filteredRows = rows.where((item) {
      final map = item as Map<String, dynamic>;
      final rowDate = '${map['ALL_TI_YMD'] ?? ''}'.trim();
      return rowDate.isEmpty || rowDate == targetYmd;
    }).toList();
    if (filteredRows.isEmpty) {
      throw Exception('해당 날짜의 시간표 데이터가 없어요.');
    }

    filteredRows.sort((a, b) {
      final aPerio = int.tryParse('${(a as Map<String, dynamic>)['PERIO'] ?? ''}') ?? 0;
      final bPerio = int.tryParse('${(b as Map<String, dynamic>)['PERIO'] ?? ''}') ?? 0;
      return aPerio.compareTo(bPerio);
    });

    return filteredRows.map((item) {
      final map = item as Map<String, dynamic>;
      final subject = '${map['ITRT_CNTNT'] ?? ''}'.trim();
      return subject.isEmpty ? '수업 정보 없음' : subject;
    }).toList();
  }

  static Future<List<String>> fetchMeal(DateTime date) async {
    if (!NeisApiConfig.hasApiKey) {
      throw Exception('NEIS_API_KEY가 비어 있어요. 발급받은 키를 연결해 주세요.');
    }

    final targetYmd = _formatYmd(date);
    final uri = Uri.https('open.neis.go.kr', '/hub/mealServiceDietInfo', {
      'KEY': NeisApiConfig.apiKey,
      'Type': 'json',
      'ATPT_OFCDC_SC_CODE': NeisApiConfig.officeCode,
      'SD_SCHUL_CODE': NeisApiConfig.schoolCode,
      'MLSV_YMD': targetYmd,
      'CACHE_BUST': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('급식 조회에 실패했어요 (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = _extractRows(decoded, 'mealServiceDietInfo');
    final filteredRows = rows.where((item) {
      final map = item as Map<String, dynamic>;
      final rowDate = '${map['MLSV_YMD'] ?? ''}'.trim();
      return rowDate.isEmpty || rowDate == targetYmd;
    }).toList();
    if (filteredRows.isEmpty) {
      throw Exception('해당 날짜의 급식 데이터가 없어요.');
    }

    final result = <String>[];
    for (final row in filteredRows) {
      final map = row as Map<String, dynamic>;
      final mealType = '${map['MMEAL_SC_NM'] ?? ''}'.trim();
      final rawMenu = '${map['DDISH_NM'] ?? ''}'.trim();
      if (rawMenu.isEmpty) continue;
      final parsed = rawMenu
          .split('<br/>')
          .map((item) => item.replaceAll(RegExp(r'\([^)]*\)'), '').trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (parsed.isEmpty) continue;
      if (mealType.isNotEmpty) {
        result.add('[$mealType]');
      }
      result.addAll(parsed);
    }

    if (result.isEmpty) {
      throw Exception('급식 메뉴 데이터가 비어 있어요.');
    }
    return result;
  }
}

class YonggongiApp extends StatelessWidget {
  const YonggongiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '영공이',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          primary: AppColors.blue,
          secondary: AppColors.navy,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.surface,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: AppColors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.white,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}

enum AppSubPage { timetable, meal, notice, meritDetail }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  AppSubPage? _activeSubPage;

  void _openSubPage(AppSubPage page) {
    setState(() => _activeSubPage = page);
  }

  void _closeSubPage() {
    setState(() => _activeSubPage = null);
  }

  void _handleQuickMenuTap(String label) {
    if (label == '시간표') {
      _openSubPage(AppSubPage.timetable);
      return;
    }

    if (label == '급식') {
      _openSubPage(AppSubPage.meal);
      return;
    }

    if (label == '공지') {
      _openSubPage(AppSubPage.notice);
      return;
    }

    if (label == '출결') {
      setState(() {
        _selectedIndex = 1;
        _activeSubPage = null;
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 기능은 준비 중이에요.')),
    );
  }

  void _handleHomeStatusTap(String type) {
    if (type == '출결') {
      setState(() {
        _selectedIndex = 1;
        _activeSubPage = null;
      });
      return;
    }

    if (type == '상벌점') {
      setState(() {
        _selectedIndex = 2;
        _activeSubPage = null;
      });
      return;
    }
  }

  Widget _buildSubPage() {
    switch (_activeSubPage) {
      case AppSubPage.timetable:
        return TimetablePage(onBack: _closeSubPage);
      case AppSubPage.meal:
        return MealPage(onBack: _closeSubPage);
      case AppSubPage.notice:
        return NoticePage(onBack: _closeSubPage);
      case AppSubPage.meritDetail:
        return MeritDetailPage(onBack: _closeSubPage);
      case null:
        final pages = [
          HomePage(
            onQuickMenuTap: _handleQuickMenuTap,
            onStatusCardTap: _handleHomeStatusTap,
          ),
          const AttendancePage(),
          MeritPage(onOpenDetail: () => _openSubPage(AppSubPage.meritDetail)),
          const ProfilePage(),
        ];
        return pages[_selectedIndex];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: _buildSubPage(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE8ECF0), width: 1),
          ),
        ),
        child: NavigationBar(
          backgroundColor: AppColors.white,
          indicatorColor: AppColors.blue.withAlpha(26),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
              _activeSubPage = null;
            });
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.blue),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded, color: AppColors.blue),
              label: '출결',
            ),
            NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events_rounded, color: AppColors.blue),
              label: '상벌점',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded, color: AppColors.blue),
              label: '마이',
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onQuickMenuTap,
    required this.onStatusCardTap,
  });

  final void Function(String label) onQuickMenuTap;
  final void Function(String type) onStatusCardTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _GradientHeader(
          title: '영공이',
          subtitle: '학교 생활을 한 곳에서',
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _StatusCard(
            title: '오늘 출결',
            value: '정상 등교',
            hint: '입실 08:27 · 하교 기록 대기',
            icon: Icons.how_to_reg_rounded,
            onTap: () => onStatusCardTap('출결'),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _StatusCard(
            title: '상벌점 현황',
            value: '+3점',
            hint: '이번 달 누적 · 상세 내역은 상벌점 탭',
            icon: Icons.emoji_events_rounded,
            onTap: () => onStatusCardTap('상벌점'),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _QuickMenuGrid(onTap: onQuickMenuTap),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        _GradientHeader(title: '출결', subtitle: '오늘 등교 기록과 최근 현황'),
        SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _SectionHeader(title: '오늘 출결', subtitle: ''),
        ),
        SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '오늘 상태', value: '정상 등교'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '입실 시간', value: '08:27'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '하교 시간', value: '기록 전'),
        ),
        SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _SectionHeader(title: '최근 기록', subtitle: '최근 5일'),
        ),
        SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _RecordRow(date: '06/20', status: '정상'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _RecordRow(date: '06/19', status: '지각'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _RecordRow(date: '06/18', status: '정상'),
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late Future<List<String>> _futureTimetable;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _futureTimetable = NeisApiService.fetchTimetable(_selectedDate);
  }

  void _changeDay(int diff) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: diff));
      _futureTimetable = NeisApiService.fetchTimetable(_selectedDate);
    });
  }

  String _dateLabel() {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _weekdayText(DateTime date) {
    const labels = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return labels[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SubPageHeader(
          title: '시간표',
          subtitle: 'NEIS에서 실시간으로 불러와요',
          onBack: widget.onBack,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _changeDay(-1),
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.blue),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '조회 날짜: ${_dateLabel()}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _changeDay(1),
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
              ),
            ],
          ),
        ),
        FutureBuilder<List<String>>(
          future: _futureTimetable,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              final message = '${snapshot.error}';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ApiErrorCard(
                  title: '시간표 불러오기 실패',
                  message: message,
                  isMissingKey: message.contains('NEIS_API_KEY'),
                ),
              );
            }

            final periods = snapshot.data ?? [];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ScheduleDayCard(day: _weekdayText(_selectedDate), periods: periods),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class MealPage extends StatefulWidget {
  const MealPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<MealPage> createState() => _MealPageState();
}

class _MealPageState extends State<MealPage> {
  late Future<List<String>> _futureMeal;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _futureMeal = NeisApiService.fetchMeal(_selectedDate);
  }

  void _changeDay(int diff) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: diff));
      _futureMeal = NeisApiService.fetchMeal(_selectedDate);
    });
  }

  String _dateLabel() {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SubPageHeader(
          title: '급식',
          subtitle: 'NEIS에서 실시간으로 불러와요',
          onBack: widget.onBack,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _changeDay(-1),
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.blue),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '조회 날짜: ${_dateLabel()}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _changeDay(1),
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
              ),
            ],
          ),
        ),
        FutureBuilder<List<String>>(
          future: _futureMeal,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              final message = '${snapshot.error}';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ApiErrorCard(
                  title: '급식 불러오기 실패',
                  message: message,
                  isMissingKey: message.contains('NEIS_API_KEY'),
                ),
              );
            }

            final menuItems = snapshot.data ?? [];
            final mealDate =
                '${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _MealCard(
                mealType: '$mealDate 급식',
                menuItems: menuItems,
                icon: Icons.lunch_dining_outlined,
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class NoticePage extends StatelessWidget {
  const NoticePage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SubPageHeader(
          title: '공지',
          subtitle: '학교 공지와 일정을 확인해요',
          onBack: onBack,
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _SectionHeader(title: '최근 공지', subtitle: ''),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '7/1 동아리 신청 마감', value: '오늘 18:00'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '기말고사 시간표 안내', value: '업데이트됨'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '체육대회 예선 일정', value: '다음 주'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class MeritPage extends StatelessWidget {
  const MeritPage({super.key, required this.onOpenDetail});

  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _GradientHeader(title: '상벌점', subtitle: '이번 달 보상 및 감점 현황'),
        const SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _StatusCard(
            title: '총 점수',
            value: '+3점',
            hint: '보상 +5 · 감점 -2',
            icon: Icons.stars_rounded,
            onTap: onOpenDetail,
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '최근 보상', value: '학급 봉사 +2'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '최근 감점', value: '지각 -1'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class MeritDetailPage extends StatelessWidget {
  const MeritDetailPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SubPageHeader(
          title: '상벌점 상세',
          subtitle: '점수 내역을 확인해요',
          onBack: onBack,
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '학급 봉사', value: '+2점'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '청소 우수', value: '+3점'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '지각', value: '-1점'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '복장 규정', value: '-1점'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _GradientHeader(title: '마이', subtitle: '내 정보와 설정'),
        const SizedBox(height: 24),
        Center(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.blue, width: 3),
            ),
            child: const CircleAvatar(
              radius: 38,
              backgroundColor: AppColors.surface,
              child: Icon(Icons.person_rounded, size: 40, color: AppColors.blue),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '익명 학생',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.blue.withAlpha(26),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('2학년 · 레벨 4', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '학급', value: '2학년 3반'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '알림 설정', value: '켜짐'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _InfoTile(label: '앱 버전', value: '0.0.1'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.hint,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String value;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withAlpha(15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.blue, AppColors.navy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF8A94A6))),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy)),
                    const SizedBox(height: 2),
                    Text(hint, style: const TextStyle(fontSize: 12, color: Color(0xFF8A94A6))),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: onTap == null ? const Color(0xFFCDD4DF) : AppColors.blue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickMenuGrid extends StatelessWidget {
  const _QuickMenuGrid({required this.onTap});

  final void Function(String label) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('바로가기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _QuickTile(
              icon: Icons.calendar_month_outlined,
              label: '시간표',
              onTap: () => onTap('시간표'),
            ),
            _QuickTile(
              icon: Icons.lunch_dining_outlined,
              label: '급식',
              onTap: () => onTap('급식'),
            ),
            _QuickTile(
              icon: Icons.campaign_outlined,
              label: '공지',
              onTap: () => onTap('공지'),
            ),
            _QuickTile(
              icon: Icons.fact_check_outlined,
              label: '출결',
              onTap: () => onTap('출결'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withAlpha(12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.blue),
                ),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubPageHeader extends StatelessWidget {
  const _SubPageHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 10, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navy, AppColors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(18),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, color: AppColors.white),
                    SizedBox(width: 4),
                    Text(
                      '뒤로',
                      style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.white.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleDayCard extends StatelessWidget {
  const _ScheduleDayCard({
    required this.day,
    required this.periods,
  });

  final String day;
  final List<String> periods;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(day, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < periods.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text('${i + 1}교시 ${periods[i]}', style: const TextStyle(color: AppColors.navy)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.mealType,
    required this.menuItems,
    required this.icon,
  });

  final String mealType;
  final List<String> menuItems;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.blue),
              const SizedBox(width: 8),
              Text(mealType, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in menuItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $item', style: const TextStyle(color: Color(0xFF5A6478))),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF8A94A6))),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF5A6478)))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
        ],
      ),
    );
  }
}

class _ApiErrorCard extends StatelessWidget {
  const _ApiErrorCard({
    required this.title,
    required this.message,
    required this.isMissingKey,
  });

  final String title;
  final String message;
  final bool isMissingKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: Color(0xFF5A6478)),
          ),
          if (isMissingKey) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.blue.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '해결 방법: 실행/빌드할 때 --dart-define=NEIS_API_KEY=발급키 를 추가해 주세요.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.date, required this.status});

  final String date;
  final String status;

  @override
  Widget build(BuildContext context) {
    final isLate = status == '지각';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isLate ? const Color(0xFFFFF0F0) : AppColors.blue.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isLate ? Icons.warning_amber_rounded : Icons.check_rounded,
              size: 18,
              color: isLate ? Colors.redAccent : AppColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(date, style: const TextStyle(color: Color(0xFF5A6478)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isLate ? const Color(0xFFFFF0F0) : AppColors.blue.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isLate ? Colors.redAccent : AppColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 그라디언트 헤더 (각 탭 상단) ──────────────────
class _GradientHeader extends StatelessWidget {
  const _GradientHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navy, AppColors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: AppColors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.white.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}
