import 'package:flutter/material.dart';

import '../../operations_models.dart';
import 'service_card_widget.dart';

class ServiceExecutionForm extends StatefulWidget {
  final ServiceModel service;
  final Map<String, dynamic> phaseSpecificData;
  final bool readOnly;
  final void Function(String key, String value) onChanged;

  const ServiceExecutionForm({
    super.key,
    required this.service,
    required this.phaseSpecificData,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<ServiceExecutionForm> createState() => _ServiceExecutionFormState();
}

class _ServiceExecutionFormState extends State<ServiceExecutionForm> {
  final Map<String, TextEditingController> _ctrl = {};

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _ctrl.clear();
    super.dispose();
  }

  TextEditingController _controllerFor(String key) {
    return _ctrl.putIfAbsent(key, () => TextEditingController());
  }

  void _sync(String key) {
    final v = (widget.phaseSpecificData[key] ?? '').toString();
    final c = _controllerFor(key);
    if (c.text != v) {
      c.text = v;
      c.selection = TextSelection.fromPosition(
        TextPosition(offset: c.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = techAllowedServiceTypeFrom(widget.service);

    final fields = <_FieldSpec>[];

    switch (type) {
      case TechAllowedServiceType.installation:
        fields.addAll(const [
          _FieldSpec(
            keyName: 'equipmentInstalled',
            label: 'Equipos instalados',
            hint: 'Ej: 4 cámaras, 1 DVR…',
            maxLines: 2,
          ),
          _FieldSpec(
            keyName: 'cableMetersUsed',
            label: 'Metros de cable usados',
            hint: 'Ej: 35',
            keyboardType: TextInputType.number,
          ),
        ]);
        break;
      case TechAllowedServiceType.maintenance:
        fields.addAll(const [
          _FieldSpec(
            keyName: 'maintenancePerformed',
            label: 'Mantenimiento realizado',
            hint: 'Ej: Limpieza, ajuste, pruebas…',
            maxLines: 2,
          ),
          _FieldSpec(
            keyName: 'equipmentCondition',
            label: 'Condición de equipos',
            hint: 'Ej: Bueno / Regular / Malo',
            maxLines: 2,
          ),
        ]);
        break;
      case TechAllowedServiceType.warranty:
        fields.addAll(const [
          _FieldSpec(
            keyName: 'failureDetected',
            label: 'Falla detectada',
            hint: 'Describe la falla encontrada',
            maxLines: 2,
          ),
          _FieldSpec(
            keyName: 'partsReplaced',
            label: 'Piezas reemplazadas',
            hint: 'Ej: Fuente, cámara, conector…',
            maxLines: 2,
          ),
        ]);
        break;
      case TechAllowedServiceType.survey:
        fields.addAll(const [
          _FieldSpec(
            keyName: 'equipmentRequired',
            label: 'Equipos requeridos',
            hint: 'Ej: 6 cámaras, 1 NVR, disco 2TB…',
            maxLines: 2,
          ),
          _FieldSpec(
            keyName: 'estimatedMaterials',
            label: 'Materiales estimados',
            hint: 'Ej: 80m cable, canaletas, conectores…',
            maxLines: 2,
          ),
        ]);
        break;
      case TechAllowedServiceType.other:
        // Not shown for technicians; kept empty.
        break;
    }

    if (fields.isEmpty) {
      return const SizedBox.shrink();
    }

    for (final f in fields) {
      _sync(f.keyName);
    }

    return Column(
      children: [
        for (final f in fields) ...[
          TextField(
            controller: _controllerFor(f.keyName),
            readOnly: widget.readOnly,
            keyboardType: f.keyboardType,
            minLines: 1,
            maxLines: f.maxLines,
            decoration: InputDecoration(labelText: f.label, hintText: f.hint),
            onChanged: (v) => widget.onChanged(f.keyName, v),
          ),
          if (f != fields.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _FieldSpec {
  final String keyName;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  const _FieldSpec({
    required this.keyName,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });
}
