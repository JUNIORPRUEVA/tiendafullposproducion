import { Role } from '@prisma/client';

export type JwtUser = {
  sub: string;
  email: string;
  role: Role;
};

