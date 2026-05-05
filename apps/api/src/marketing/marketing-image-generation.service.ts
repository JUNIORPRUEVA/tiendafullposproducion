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
    const placeholderUrl = this.buildProfessionalPlaceholderUrl(input);
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
        headline: this.truncate(input.title, 72),
        cta: this.truncate(input.cta, 44),
      },
    };
  }

  private buildProfessionalPlaceholderUrl(input: ImageGenerationInput) {
    const headline = this.truncate(input.title, 72);
    const cta = this.truncate(input.cta, 44);
    const base = (input.baseImageUrl || '').trim();

    if (base.startsWith('http://') || base.startsWith('https://')) {
      // Keep the selected gallery image as visual base in 9:16 format.
      const normalized = base.replace(/^https?:\/\//, '');
      return `https://images.weserv.nl/?url=${encodeURIComponent(normalized)}&w=1080&h=1920&fit=cover&output=jpg&q=82`;
    }

    const lines = `${headline}\n${cta}`.trim();
    return `https://placehold.co/1080x1920/101828/F8FAFC/png?text=${encodeURIComponent(lines)}`;
  }

  private truncate(value: string, max: number) {
    const clean = (value || '').replace(/\s+/g, ' ').trim();
    if (clean.length <= max) return clean;
    return `${clean.slice(0, Math.max(0, max - 3)).trim()}...`;
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
