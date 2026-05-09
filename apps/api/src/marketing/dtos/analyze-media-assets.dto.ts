import { ArrayMaxSize, IsEnum, IsNotEmpty, IsString } from 'class-validator';

export class AnalyzeMediaAssetsDto {
  @IsString({ each: true })
  @ArrayMaxSize(5)
  @IsNotEmpty()
  mediaAssetIds!: string[];

  @IsEnum(['sales', 'trust', 'educational'], { always: true })
  storyType!: 'sales' | 'trust' | 'educational';
}
