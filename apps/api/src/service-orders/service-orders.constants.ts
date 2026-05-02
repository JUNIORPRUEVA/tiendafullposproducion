import {
  ServiceEvidenceType,
  ServiceOrderCategory,
  ServiceOrderStatus,
  ServiceReportType,
  ServiceOrderType,
} from '@prisma/client';

export const SERVICE_ORDER_CATEGORY_VALUES = [
  'camara',
  'motor_porton',
  'alarma',
  'cerco_electrico',
  'intercom',
  'punto_venta',
] as const;

export const SERVICE_ORDER_TYPE_VALUES = [
  'instalacion',
  'mantenimiento',
  'levantamiento',
  'garantia',
] as const;

export const SERVICE_ORDER_STATUS_VALUES = [
  'pendiente',
  'en_proceso',
  'en_pausa',
  'pospuesta',
  'finalizado',
  'cancelado',
] as const;

export const SERVICE_EVIDENCE_TYPE_VALUES = [
  'referencia_texto',
  'referencia_imagen',
  'referencia_video',
  'evidencia_texto',
  'evidencia_imagen',
  'evidencia_video',
] as const;

export const SERVICE_REPORT_TYPE_VALUES = [
  'requerimiento_cliente',
  'servicio_finalizado',
  'otros',
] as const;

export type ApiServiceOrderCategory = (typeof SERVICE_ORDER_CATEGORY_VALUES)[number];
export type ApiServiceOrderType = (typeof SERVICE_ORDER_TYPE_VALUES)[number];
export type ApiServiceOrderStatus = (typeof SERVICE_ORDER_STATUS_VALUES)[number];
export type ApiServiceEvidenceType = (typeof SERVICE_EVIDENCE_TYPE_VALUES)[number];
export type ApiServiceReportType = (typeof SERVICE_REPORT_TYPE_VALUES)[number];

const asServiceEvidenceType = (value: ApiServiceEvidenceType): ServiceEvidenceType => {
  return value.toUpperCase() as unknown as ServiceEvidenceType;
};

const asServiceReportType = (value: ApiServiceReportType): ServiceReportType => {
  return value.toUpperCase() as unknown as ServiceReportType;
};

export const SERVICE_ORDER_CATEGORY_TO_DB: Record<ApiServiceOrderCategory, ServiceOrderCategory> = {
  camara: ServiceOrderCategory.CAMARA,
  motor_porton: ServiceOrderCategory.MOTOR_PORTON,
  alarma: ServiceOrderCategory.ALARMA,
  cerco_electrico: ServiceOrderCategory.CERCO_ELECTRICO,
  intercom: ServiceOrderCategory.INTERCOM,
  punto_venta: ServiceOrderCategory.PUNTO_VENTA,
};

export const SERVICE_ORDER_CATEGORY_FROM_DB: Record<ServiceOrderCategory, ApiServiceOrderCategory> = {
  [ServiceOrderCategory.CAMARA]: 'camara',
  [ServiceOrderCategory.MOTOR_PORTON]: 'motor_porton',
  [ServiceOrderCategory.ALARMA]: 'alarma',
  [ServiceOrderCategory.CERCO_ELECTRICO]: 'cerco_electrico',
  [ServiceOrderCategory.INTERCOM]: 'intercom',
  [ServiceOrderCategory.PUNTO_VENTA]: 'punto_venta',
};

export const SERVICE_ORDER_TYPE_TO_DB: Record<ApiServiceOrderType, ServiceOrderType> = {
  instalacion: ServiceOrderType.INSTALACION,
  mantenimiento: ServiceOrderType.MANTENIMIENTO,
  levantamiento: ServiceOrderType.LEVANTAMIENTO,
  garantia: ServiceOrderType.GARANTIA,
};

export const SERVICE_ORDER_TYPE_FROM_DB: Record<ServiceOrderType, ApiServiceOrderType> = {
  [ServiceOrderType.INSTALACION]: 'instalacion',
  [ServiceOrderType.MANTENIMIENTO]: 'mantenimiento',
  [ServiceOrderType.LEVANTAMIENTO]: 'levantamiento',
  [ServiceOrderType.GARANTIA]: 'garantia',
};

export const SERVICE_ORDER_STATUS_TO_DB: Record<ApiServiceOrderStatus, ServiceOrderStatus> = {
  pendiente: ServiceOrderStatus.PENDIENTE,
  en_proceso: ServiceOrderStatus.EN_PROCESO,
  en_pausa: ServiceOrderStatus.EN_PAUSA,
  pospuesta: ServiceOrderStatus.POSPUESTA,
  finalizado: ServiceOrderStatus.FINALIZADO,
  cancelado: ServiceOrderStatus.CANCELADO,
};

export const SERVICE_ORDER_STATUS_FROM_DB: Record<ServiceOrderStatus, ApiServiceOrderStatus> = {
  [ServiceOrderStatus.PENDIENTE]: 'pendiente',
  [ServiceOrderStatus.EN_PROCESO]: 'en_proceso',
  [ServiceOrderStatus.EN_PAUSA]: 'en_pausa',
  [ServiceOrderStatus.POSPUESTA]: 'pospuesta',
  [ServiceOrderStatus.FINALIZADO]: 'finalizado',
  [ServiceOrderStatus.CANCELADO]: 'cancelado',
};

export const SERVICE_EVIDENCE_TYPE_TO_DB: Record<ApiServiceEvidenceType, ServiceEvidenceType> = {
  referencia_texto: asServiceEvidenceType('referencia_texto'),
  referencia_imagen: asServiceEvidenceType('referencia_imagen'),
  referencia_video: asServiceEvidenceType('referencia_video'),
  evidencia_texto: asServiceEvidenceType('evidencia_texto'),
  evidencia_imagen: asServiceEvidenceType('evidencia_imagen'),
  evidencia_video: asServiceEvidenceType('evidencia_video'),
};

export const SERVICE_EVIDENCE_TYPE_FROM_DB: Record<string, ApiServiceEvidenceType> = {
  REFERENCIA_TEXTO: 'referencia_texto',
  REFERENCIA_IMAGEN: 'referencia_imagen',
  REFERENCIA_VIDEO: 'referencia_video',
  EVIDENCIA_TEXTO: 'evidencia_texto',
  EVIDENCIA_IMAGEN: 'evidencia_imagen',
  EVIDENCIA_VIDEO: 'evidencia_video',
};

export const SERVICE_REPORT_TYPE_TO_DB: Record<ApiServiceReportType, ServiceReportType> = {
  requerimiento_cliente: asServiceReportType('requerimiento_cliente'),
  servicio_finalizado: asServiceReportType('servicio_finalizado'),
  otros: asServiceReportType('otros'),
};

export const SERVICE_REPORT_TYPE_FROM_DB: Record<string, ApiServiceReportType> = {
  REQUERIMIENTO_CLIENTE: 'requerimiento_cliente',
  SERVICIO_FINALIZADO: 'servicio_finalizado',
  OTROS: 'otros',
};

export const SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS: Record<
  ApiServiceOrderStatus,
  ApiServiceOrderStatus[]
> = {
  pendiente: ['en_proceso', 'pospuesta', 'cancelado'],
  en_proceso: ['en_pausa', 'finalizado', 'pospuesta', 'cancelado'],
  en_pausa: ['en_proceso', 'pospuesta', 'cancelado'],
  pospuesta: ['pendiente', 'cancelado'],
  finalizado: [],
  cancelado: ['pospuesta'],
};