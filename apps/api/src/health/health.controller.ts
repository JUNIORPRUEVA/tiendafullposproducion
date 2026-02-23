import { Controller, Get } from '@nestjs/common';

@Controller()
export class HealthController {
  @Get()
  getRootHealth() {
    return { status: 'ok' };
  }

  @Get('health')
  getHealth() {
    return { status: 'ok' };
  }
}

