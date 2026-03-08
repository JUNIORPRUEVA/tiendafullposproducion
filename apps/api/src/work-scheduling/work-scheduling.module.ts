import { Module } from '@nestjs/common';
import { WorkSchedulingController } from './work-scheduling.controller';
import { WorkSchedulingService } from './work-scheduling.service';

@Module({
  controllers: [WorkSchedulingController],
  providers: [WorkSchedulingService],
})
export class WorkSchedulingModule {}
