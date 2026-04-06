import { IsIn, IsOptional } from 'class-validator';

const ORDER_DOCUMENT_FLOW_STATUS_VALUES = [
  'pending_preparation',
  'ready_for_review',
  'ready_for_finalization',
  'approved',
  'rejected',
  'sent',
] as const;

export class ListOrderDocumentFlowsQueryDto {
  @IsOptional()
  @IsIn(ORDER_DOCUMENT_FLOW_STATUS_VALUES)
  status?: string;
}