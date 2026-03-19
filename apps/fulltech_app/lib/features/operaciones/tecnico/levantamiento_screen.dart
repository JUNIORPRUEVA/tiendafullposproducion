import 'package:flutter/widgets.dart';

import 'technical_phase_form_screen.dart';

class LevantamientoScreen extends StatelessWidget {
  final String serviceId;

  const LevantamientoScreen({super.key, required this.serviceId});

  @override
  Widget build(BuildContext context) {
    return TechnicalPhaseFormScreen(
      serviceId: serviceId,
      variant: TechnicalPhaseFormVariant.levantamiento,
    );
  }
}
