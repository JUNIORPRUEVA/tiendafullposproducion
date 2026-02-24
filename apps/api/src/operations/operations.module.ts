import { Module } from '@nestjs/common';
import { OperationsService } from './operations-main.service';
import { OperationsController } from './operations.controller';

@Module({
  imports: [],
  controllers: [OperationsController],
  providers: [OperationsService],
  exports: [OperationsService],
})
export class OperationsModule {}
