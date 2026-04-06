import { IsObject, IsOptional } from 'class-validator';

export class EditOrderDocumentFlowDraftDto {
  @IsOptional()
  @IsObject()
  invoiceDraftJson?: Record<string, unknown> | null;

  @IsOptional()
  @IsObject()
  warrantyDraftJson?: Record<string, unknown> | null;
}