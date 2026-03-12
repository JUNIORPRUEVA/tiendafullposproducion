import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/work_scheduling_admin_controller.dart';
import 'application/work_scheduling_week_controller.dart';
import 'horarios_models.dart';
import 'presentation/admin/admin_calendar_page.dart';
import 'presentation/admin/admin_employees_page.dart';
import 'presentation/admin/admin_exceptions_page.dart';
import 'presentation/admin/admin_history_page.dart';
import 'presentation/admin/admin_home_page.dart';
import 'presentation/admin/admin_rules_page.dart';
import 'presentation/employee/employee_calendar_page.dart';
import 'presentation/employee/employee_home_page.dart';
import 'presentation/employee/employee_profile_page.dart';
import 'presentation/employee/employee_requests_page.dart';

class HorariosScreen extends ConsumerStatefulWidget {
  const HorariosScreen({super.key});

  @override
  ConsumerState<HorariosScreen> createState() => _HorariosScreenState();
}

class _HorariosScreenState extends ConsumerState<HorariosScreen> {
  bool _loadedAdminBasics = false;
  String? _loadedExceptionsWeekStart;

  int _adminIndex = 0;
  int _employeeIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final user = ref.read(authStateProvider).user;
    final isAdmin = (user?.role ?? '').toUpperCase() == 'ADMIN';
    if (!isAdmin) return;

    final admin = ref.read(workSchedulingAdminControllerProvider.notifier);
    if (!_loadedAdminBasics) {
      _loadedAdminBasics = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        admin.loadBasics();
      });
    }

    final weekStart = ref.read(workSchedulingWeekControllerProvider).weekStart;
    final weekStartIso = dateOnly(weekStart);
    if (_loadedExceptionsWeekStart != weekStartIso) {
      _loadedExceptionsWeekStart = weekStartIso;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        admin.loadExceptionsForWeek(weekStartIso);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = (user?.role ?? '').toUpperCase() == 'ADMIN';

    final isWide = MediaQuery.sizeOf(context).width >= 980;
    final scheme = Theme.of(context).colorScheme;

    final adminPages = <Widget>[
      const WorkSchedulingAdminHomePage(),
      const WorkSchedulingAdminCalendarPage(),
      const WorkSchedulingAdminEmployeesPage(),
      const WorkSchedulingAdminRulesPage(),
      const WorkSchedulingAdminExceptionsPage(),
      const WorkSchedulingAdminHistoryPage(),
    ];

    final employeePages = <Widget>[
      WorkSchedulingEmployeeHomePage(
        onOpenCalendar: () => setState(() => _employeeIndex = 1),
      ),
      const WorkSchedulingEmployeeCalendarPage(),
      const WorkSchedulingEmployeeRequestsPage(),
      const WorkSchedulingEmployeeProfilePage(),
    ];

    final adminDestinations = const <NavigationRailDestination>[
      NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard_rounded),
        label: Text('Resumen'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month_rounded),
        label: Text('Calendario'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.people_alt_outlined),
        selectedIcon: Icon(Icons.people_alt_rounded),
        label: Text('Empleados'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.rule_folder_outlined),
        selectedIcon: Icon(Icons.rule_folder_rounded),
        label: Text('Reglas'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.event_busy_outlined),
        selectedIcon: Icon(Icons.event_busy_rounded),
        label: Text('Excepciones'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history_rounded),
        label: Text('Historial'),
      ),
    ];

    final employeeDestinations = const <NavigationRailDestination>[
      NavigationRailDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: Text('Inicio'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month_rounded),
        label: Text('Calendario'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.assignment_outlined),
        selectedIcon: Icon(Icons.assignment_rounded),
        label: Text('Solicitudes'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person_rounded),
        label: Text('Perfil'),
      ),
    ];

    final currentIndex = isAdmin ? _adminIndex : _employeeIndex;
    final pages = isAdmin ? adminPages : employeePages;

    void onSelect(int i) {
      setState(() {
        if (isAdmin) {
          _adminIndex = i;
        } else {
          _employeeIndex = i;
        }
      });

      if (isAdmin && i == 5) {
        final admin = ref.read(workSchedulingAdminControllerProvider.notifier);
        final s = ref.read(workSchedulingAdminControllerProvider);
        if (s.audit.isEmpty && !s.loading) {
          admin.loadAuditAndReports();
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin ? 'Horarios • Administrador' : 'Horarios • Mi espacio',
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: onSelect,
                  destinations: isAdmin
                      ? adminDestinations
                      : employeeDestinations,
                  backgroundColor: scheme.surface,
                  indicatorColor: scheme.primaryContainer.withValues(
                    alpha: 0.9,
                  ),
                  selectedIconTheme: IconThemeData(color: scheme.primary),
                  selectedLabelTextStyle: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  labelType: NavigationRailLabelType.all,
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.65),
                ),
                Expanded(child: pages[currentIndex]),
              ],
            )
          : pages[currentIndex],
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: onSelect,
              destinations: isAdmin
                  ? const [
                      NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: 'Resumen',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.calendar_month_outlined),
                        selectedIcon: Icon(Icons.calendar_month_rounded),
                        label: 'Calendario',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.people_alt_outlined),
                        selectedIcon: Icon(Icons.people_alt_rounded),
                        label: 'Empleados',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.rule_folder_outlined),
                        selectedIcon: Icon(Icons.rule_folder_rounded),
                        label: 'Reglas',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.event_busy_outlined),
                        selectedIcon: Icon(Icons.event_busy_rounded),
                        label: 'Excepciones',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.history_outlined),
                        selectedIcon: Icon(Icons.history_rounded),
                        label: 'Historial',
                      ),
                    ]
                  : const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Inicio',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.calendar_month_outlined),
                        selectedIcon: Icon(Icons.calendar_month_rounded),
                        label: 'Calendario',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.assignment_outlined),
                        selectedIcon: Icon(Icons.assignment_rounded),
                        label: 'Solicitudes',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: 'Perfil',
                      ),
                    ],
            ),
    );
  }
}
