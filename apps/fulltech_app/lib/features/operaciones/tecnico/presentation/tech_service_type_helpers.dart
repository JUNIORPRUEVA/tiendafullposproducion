import '../../operations_models.dart';

enum TechAllowedServiceType {
  installation,
  maintenance,
  warranty,
  survey,
  other,
}

TechAllowedServiceType techAllowedServiceTypeFrom(ServiceModel service) {
  final key = _normalizeKey(service.serviceType);
  switch (key) {
    case 'installation':
    case 'instalacion':
      return TechAllowedServiceType.installation;
    case 'maintenance':
    case 'mantenimiento':
      return TechAllowedServiceType.maintenance;
    case 'warranty':
    case 'garantia':
      return TechAllowedServiceType.warranty;
    case 'survey':
    case 'levantamiento':
      return TechAllowedServiceType.survey;
    default:
      return TechAllowedServiceType.other;
  }
}

String _normalizeKey(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return '';

  value = value
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  return value.replaceAll(' ', '_').replaceAll('-', '_');
}
