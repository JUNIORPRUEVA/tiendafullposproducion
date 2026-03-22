import {
  ServiceEvidenceType,
  ServiceOrderCategory,
  ServiceOrderStatus,
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
  'finalizado',
  'cancelado',
] as const;

export const SERVICE_EVIDENCE_TYPE_VALUES = ['texto', 'imagen', 'video'] as const;

export type ApiServiceOrderCategory = (typeof SERVICE_ORDER_CATEGORY_VALUES)[number];
export type ApiServiceOrderType = (typeof SERVICE_ORDER_TYPE_VALUES)[number];
export type ApiServiceOrderStatus = (typeof SERVICE_ORDER_STATUS_VALUES)[number];
export type ApiServiceEvidenceType = (typeof SERVICE_EVIDENCE_TYPE_VALUES)[number];

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
  finalizado: ServiceOrderStatus.FINALIZADO,
  cancelado: ServiceOrderStatus.CANCELADO,
};

export const SERVICE_ORDER_STATUS_FROM_DB: Record<ServiceOrderStatus, ApiServiceOrderStatus> = {
  [ServiceOrderStatus.PENDIENTE]: 'pendiente',
  [ServiceOrderStatus.EN_PROCESO]: 'en_proceso',
  [ServiceOrderStatus.FINALIZADO]: 'finalizado',
  [ServiceOrderStatus.CANCELADO]: 'cancelado',
};

export const SERVICE_EVIDENCE_TYPE_TO_DB: Record<ApiServiceEvidenceType, ServiceEvidenceType> = {
  texto: ServiceEvidenceType.TEXTO,
  imagen: ServiceEvidenceType.IMAGEN,
  video: ServiceEvidenceType.VIDEO,
};

export const SERVICE_EVIDENCE_TYPE_FROM_DB: Record<ServiceEvidenceType, ApiServiceEvidenceType> = {
  [ServiceEvidenceType.TEXTO]: 'texto',
  [ServiceEvidenceType.IMAGEN]: 'imagen',
  [ServiceEvidenceType.VIDEO]: 'video',
};

export const SERVICE_ORDER_ALLOWED_STATUS_TRANSITIONS: Record<
  ApiServiceOrderStatus,
  ApiServiceOrderStatus[]
> = {
  pendiente: ['en_proceso', 'cancelado'],
  en_proceso: ['finalizado', 'cancelado'],
  finalizado: [],
  cancelado: [],
};