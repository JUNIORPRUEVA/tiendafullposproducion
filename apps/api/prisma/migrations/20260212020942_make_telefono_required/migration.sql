/*
  Warnings:

  - Made the column `telefono` on table `Client` required. This step will fail if there are existing NULL values in that column.

*/
-- AlterTable
ALTER TABLE "Category" ALTER COLUMN "id" DROP DEFAULT;

-- AlterTable
ALTER TABLE "Client" ALTER COLUMN "telefono" SET NOT NULL;

-- AlterTable
ALTER TABLE "Sale" ALTER COLUMN "id" DROP DEFAULT,
ALTER COLUMN "subtotal" DROP DEFAULT,
ALTER COLUMN "totalCost" DROP DEFAULT,
ALTER COLUMN "profit" DROP DEFAULT,
ALTER COLUMN "commission" DROP DEFAULT,
ALTER COLUMN "updatedAt" DROP DEFAULT;

-- AlterTable
ALTER TABLE "SaleItem" ALTER COLUMN "id" DROP DEFAULT;
