import { Injectable } from '@nestjs/common';

type ImageGenerationInput = {
  companyName: string;
  city: string;
  country: string;
  brandTone: string;
  brandColors: string[];
  title: string;
  cta: string;
  offer: string;
  visualConcept: string;
  designNotes: string;
  baseImageUrl: string;
  imageCategory: string;
  serviceOrProduct: string;
  usedResearchAngle: string;
};

type ImageGenerationResult = {
  imageStatus: 'GENERATED' | 'GENERATED_PLACEHOLDER' | 'PENDING' | 'FAILED';
  generatedImageUrl: string | null;
  generatedImageProvider: string;
  prompt: string;
  visualConcept: string;
  designNotes: string;
  metadata: Record<string, unknown>;
};

@Injectable()
export class MarketingImageGenerationService {
  async generateOrPrepare(input: ImageGenerationInput): Promise<ImageGenerationResult> {
    const prompt = this.buildPrompt(input);

    // Placeholder mode for now. Architecture ready for external providers.
    const placeholderUrl = input.baseImageUrl || 'image_placeholder_story_9_16';
    return {
      imageStatus: 'GENERATED_PLACEHOLDER',
      generatedImageUrl: placeholderUrl,
      generatedImageProvider: 'placeholder/local',
      prompt,
      visualConcept: input.visualConcept,
      designNotes: input.designNotes,
      metadata: {
        mode: 'placeholder',
        baseImageUrl: input.baseImageUrl,
        format: '9:16',
        category: input.imageCategory,
        serviceOrProduct: input.serviceOrProduct,
      },
    };
  }

  buildPrompt(input: ImageGenerationInput) {
    const colors = input.brandColors.length > 0 ? input.brandColors.join(', ') : 'azul oscuro, blanco, turquesa';
    return [
      `Crear diseño publicitario vertical 9:16 para historia de Instagram/Facebook de ${input.companyName} en ${input.city}, ${input.country}.`,
      `Usar como referencia una foto real de ${input.serviceOrProduct || input.imageCategory || 'servicio de seguridad tecnológica'} (${input.baseImageUrl || 'placeholder profesional'}).`,
      `Estilo ${input.brandTone || 'tecnológico, limpio y profesional'}.`,
      `Concepto visual: ${input.visualConcept}.`,
      `Ángulo de venta: ${input.usedResearchAngle || 'confiabilidad y resultados reales'}.`,
      `Oferta recomendada: ${input.offer || 'asesoría y cotización personalizada'}.`,
      `Texto principal: "${input.title}".`,
      `CTA: "${input.cta}".`,
      `Colores de marca: ${colors}.`,
      `Notas de diseño: ${input.designNotes}.`,
      'Diseño moderno, alta confianza, sin saturar, legible en móvil.',
    ].join(' ');
  }
}
