import { Module } from '@nestjs/common';
import { StorageModule } from '../storage/storage.module';
import { EmployeeWarningsController } from './employee-warnings.controller';
import { EmployeeWarningsService } from './employee-warnings.service';

@Module({
  imports: [StorageModule],
  controllers: [EmployeeWarningsController],
  providers: [EmployeeWarningsService],
  exports: [EmployeeWarningsService],
})
export class EmployeeWarningsModule {}
