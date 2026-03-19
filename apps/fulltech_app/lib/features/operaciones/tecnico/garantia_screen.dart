import 'package:flutter/widgets.dart';

import 'technical_phase_form_screen.dart';

class GarantiaScreen extends StatelessWidget {
  final String serviceId;

  const GarantiaScreen({super.key, required this.serviceId});

  @override
  Widget build(BuildContext context) {
    return TechnicalPhaseFormScreen(
      serviceId: serviceId,
      variant: TechnicalPhaseFormVariant.garantia,
    );
  }
}
