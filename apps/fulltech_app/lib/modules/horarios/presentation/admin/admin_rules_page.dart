import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_admin_controller.dart';
import '../../horarios_models.dart';
import '../widgets/section_header.dart';

class WorkSchedulingAdminRulesPage extends ConsumerStatefulWidget {
  const WorkSchedulingAdminRulesPage({super.key});

  @override
  ConsumerState<WorkSchedulingAdminRulesPage> createState() =>
      _WorkSchedulingAdminRulesPageState();
}

class _WorkSchedulingAdminRulesPageState
    extends ConsumerState<WorkSchedulingAdminRulesPage> {
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workSchedulingAdminControllerProvider);
    final controller = ref.read(workSchedulingAdminControllerProvider.notifier);

    for (final r in state.coverageRules) {
      final key = '${r.role}:${r.weekday}';
      _ctrls.putIfAbsent(
        key,
        () => TextEditingController(text: r.minRequired.toString()),
      );
    }

    final roles = state.coverageRules.map((e) => e.role).toSet().toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(
          title: 'Reglas',
          subtitle: 'Cobertura mínima por rol y día.',
          trailing: FilledButton.icon(
            onPressed: state.loading
                ? null
                : () {
                    final next = <WorkCoverageRule>[];
                    for (final role in roles) {
                      for (int weekday = 0; weekday < 7; weekday++) {
                        final key = '$role:$weekday';
                        final txt = _ctrls[key]?.text.trim() ?? '0';
                        final v = int.tryParse(txt) ?? 0;
                        next.add(
                          WorkCoverageRule(
                            role: role,
                            weekday: weekday,
                            minRequired: v < 0 ? 0 : v,
                          ),
                        );
                      }
                    }
                    controller.saveCoverageRules(next);
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ),
        const SizedBox(height: 12),
        if (state.error != null) ...[
          ErrorBanner(message: state.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Rol')),
                DataColumn(label: Text('Lun')),
                DataColumn(label: Text('Mar')),
                DataColumn(label: Text('Mié')),
                DataColumn(label: Text('Jue')),
                DataColumn(label: Text('Vie')),
                DataColumn(label: Text('Sáb')),
                DataColumn(label: Text('Dom')),
              ],
              rows: [
                for (final role in roles)
                  DataRow(
                    cells: [
                      DataCell(Text(role)),
                      for (int weekday = 0; weekday < 7; weekday++)
                        DataCell(
                          SizedBox(
                            width: 56,
                            child: TextField(
                              controller: _ctrls['$role:$weekday'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
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
}
