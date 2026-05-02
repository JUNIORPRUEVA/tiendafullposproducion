import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import '../application/warnings_controller.dart';
import '../../user/data/users_repository.dart';
import '../../../core/models/user_model.dart';
import 'warning_labels.dart';

class WarningCreateScreen extends ConsumerStatefulWidget {
  final EmployeeWarning? existing; // non-null = edit mode
  const WarningCreateScreen({super.key, this.existing});

  @override
  ConsumerState<WarningCreateScreen> createState() =>
      _WarningCreateScreenState();
}

class _WarningCreateScreenState extends ConsumerState<WarningCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  List<UserModel> _employees = [];
  UserModel? _selectedEmployee;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _legalCtrl = TextEditingController();
  final _ruleRefCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final _correctiveCtrl = TextEditingController();
  final _consequenceCtrl = TextEditingController();
  final _evidenceNotesCtrl = TextEditingController();

  DateTime _warningDate = DateTime.now();
  DateTime _incidentDate = DateTime.now();
  String _category = 'MISCONDUCT';
  String _severity = 'MEDIUM';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _fillFromExisting();
  }

  void _fillFromExisting() {
    final w = widget.existing;
    if (w == null) return;
    _titleCtrl.text = w.title;
    _descCtrl.text = w.description;
    _legalCtrl.text = w.legalBasis ?? '';
    _ruleRefCtrl.text = w.internalRuleReference ?? '';
    _explanationCtrl.text = w.employeeExplanation ?? '';
    _correctiveCtrl.text = w.correctiveAction ?? '';
    _consequenceCtrl.text = w.consequenceNote ?? '';
    _evidenceNotesCtrl.text = w.evidenceNotes ?? '';
    _warningDate = w.warningDate;
    _incidentDate = w.incidentDate;
    _category = w.category;
    _severity = w.severity;
  }

  Future<void> _loadEmployees() async {
    try {
      final all = await ref.read(usersRepositoryProvider).getAllUsers();
      if (mounted) {
        setState(() {
          _employees = all;
          if (widget.existing != null) {
            _selectedEmployee = all.firstWhere(
              (u) => u.id == widget.existing!.employeeUserId,
              orElse: () => all.first,
            );
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _legalCtrl.dispose();
    _ruleRefCtrl.dispose();
    _explanationCtrl.dispose();
    _correctiveCtrl.dispose();
    _consequenceCtrl.dispose();
    _evidenceNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isWarningDate) async {
    final initial = isWarningDate ? _warningDate : _incidentDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isWarningDate) {
          _warningDate = picked;
        } else {
          _incidentDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecciona un empleado'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(employeeWarningsRepositoryProvider);
      final data = {
        'employeeUserId': _selectedEmployee!.id,
        'warningDate': _warningDate.toIso8601String(),
        'incidentDate': _incidentDate.toIso8601String(),
        'title': _titleCtrl.text.trim(),
        'category': _category,
        'severity': _severity,
        if (_legalCtrl.text.isNotEmpty) 'legalBasis': _legalCtrl.text.trim(),
        if (_ruleRefCtrl.text.isNotEmpty)
          'internalRuleReference': _ruleRefCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        if (_explanationCtrl.text.isNotEmpty)
          'employeeExplanation': _explanationCtrl.text.trim(),
        if (_correctiveCtrl.text.isNotEmpty)
          'correctiveAction': _correctiveCtrl.text.trim(),
        if (_consequenceCtrl.text.isNotEmpty)
          'consequenceNote': _consequenceCtrl.text.trim(),
        if (_evidenceNotesCtrl.text.isNotEmpty)
          'evidenceNotes': _evidenceNotesCtrl.text.trim(),
      };

      if (widget.existing != null) {
        await repo.update(widget.existing!.id, data);
      } else {
        await repo.create(data);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isAdmin = ref.watch(canAccessAmonestacionesProvider);

    // Solo ADMIN puede crear/editar amonestaciones
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'Editar' : 'Nueva amonestación'),
          backgroundColor: const Color(0xFF1a1a2e),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Acceso no permitido para este usuario'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(isEdit ? 'Editar borrador' : 'Nueva amonestación',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(title: 'Empleado y fechas', children: [
              _EmployeePicker(
                employees: _employees,
                selected: _selectedEmployee,
                onChanged: (u) => setState(() => _selectedEmployee = u),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Fecha del documento',
                      value: _warningDate,
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha del incidente',
                      value: _incidentDate,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 12),
            _Section(title: 'Clasificación', children: [
              Row(
                children: [
                  Expanded(
                    child: _DropdownField(
                      label: 'Categoría',
                      value: _category,
                      options: WarningLabels.category,
                      onChanged: (v) =>
                          setState(() => _category = v ?? _category),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DropdownField(
                      label: 'Severidad',
                      value: _severity,
                      options: WarningLabels.severity,
                      onChanged: (v) =>
                          setState(() => _severity = v ?? _severity),
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 12),
            _Section(title: 'Detalles', children: [
              _TextField(
                ctrl: _titleCtrl,
                label: 'Título',
                required: true,
                maxLength: 200,
              ),
              const SizedBox(height: 10),
              _TextField(
                ctrl: _descCtrl,
                label: 'Descripción de los hechos',
                required: true,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              _TextField(
                ctrl: _explanationCtrl,
                label: 'Descargo del empleado (opcional)',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _TextField(
                ctrl: _legalCtrl,
                label: 'Base legal (opcional)',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _TextField(
                ctrl: _ruleRefCtrl,
                label: 'Referencia reglamento interno (opcional)',
              ),
            ]),
            const SizedBox(height: 12),
            _Section(title: 'Acción correctiva', children: [
              _TextField(
                ctrl: _correctiveCtrl,
                label: 'Acción correctiva requerida (opcional)',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _TextField(
                ctrl: _consequenceCtrl,
                label: 'Consecuencias (opcional)',
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              _TextField(
                ctrl: _evidenceNotesCtrl,
                label: 'Notas de evidencias (opcional)',
                maxLines: 2,
              ),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a1a2e),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(isEdit ? 'Guardar cambios' : 'Guardar borrador',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared form widgets ───────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1a1a2e),
                    letterSpacing: 0.5)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _TextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool required;
  final int maxLines;
  final int? maxLength;

  const _TextField({
    required this.ctrl,
    required this.label,
    this.required = false,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null
            : null,
      );
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final void Function(String?) onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        items: options.entries
            .map((e) =>
                DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: onChanged,
      );
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            suffixIcon: const Icon(Icons.calendar_today, size: 16),
          ),
          child: Text(WarningLabels.fmt(value),
              style: const TextStyle(fontSize: 14)),
        ),
      );
}

class _EmployeePicker extends StatelessWidget {
  final List<UserModel> employees;
  final UserModel? selected;
  final void Function(UserModel?) onChanged;

  const _EmployeePicker({
    required this.employees,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Cargando empleados…', style: TextStyle(fontSize: 13)),
        ],
      );
    }

    return DropdownButtonFormField<UserModel>(
      value: selected,
      decoration: InputDecoration(
        labelText: 'Empleado',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      ),
      items: employees
          .map((u) => DropdownMenuItem<UserModel>(
                value: u,
                child: Text(u.nombreCompleto,
                    style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Selecciona un empleado' : null,
    );
  }
}
