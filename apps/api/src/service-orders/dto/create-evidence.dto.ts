import { IsIn, IsString } from 'class-validator';
import { SERVICE_EVIDENCE_TYPE_VALUES } from '../service-orders.constants';

export class CreateEvidenceDto {
  @IsIn(SERVICE_EVIDENCE_TYPE_VALUES)
  type!: string;

  @IsString()
  content!: string;
}