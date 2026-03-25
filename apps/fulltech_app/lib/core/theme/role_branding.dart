 import 'package:flutter/material.dart';

import '../auth/app_role.dart';

class RoleBranding {
  const RoleBranding({
    required this.role,
    required this.departmentName,
    required this.departmentAccentLabel,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.appBarStart,
    required this.appBarEnd,
    required this.drawerStart,
    required this.drawerEnd,
    required this.backgroundTop,
    required this.backgroundMiddle,
    required this.backgroundBottom,
    required this.glowA,
    required this.glowB,
    required this.glowC,
    required this.watermarkTitle,
    required this.watermarkSubtitle,
  });

  final AppRole role;
  final String departmentName;
  final String departmentAccentLabel;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color appBarStart;
  final Color appBarEnd;
  final Color drawerStart;
  final Color drawerEnd;
  final Color backgroundTop;
  final Color backgroundMiddle;
  final Color backgroundBottom;
  final Color glowA;
  final Color glowB;
  final Color glowC;
  final String watermarkTitle;
  final String watermarkSubtitle;

  LinearGradient get appBarGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [appBarStart, appBarEnd],
  );

  Color get appBarStartDark => Color.alphaBlend(
    tertiary.withValues(alpha: 0.34),
    appBarStart,
  );

  Color get appBarEndDark => Color.alphaBlend(
    tertiary.withValues(alpha: 0.26),
    appBarEnd,
  );

  Color get appBarSolidColor => Color.alphaBlend(
    tertiary.withValues(alpha: 0.30),
    appBarEnd,
  );

  Color get drawerSolidColor => Color.lerp(drawerStart, drawerEnd, 0.68)!;

  LinearGradient get appBarDarkGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [appBarStartDark, appBarEndDark],
  );

  LinearGradient get drawerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [drawerStart, drawerEnd],
  );
}

RoleBranding resolveRoleBranding(AppRole role) {
  switch (role) {
    case AppRole.vendedor:
      return const RoleBranding(
        role: AppRole.vendedor,
        departmentName: 'Departamento de Ventas',
        departmentAccentLabel: 'Conversion y relacion comercial',
        primary: Color(0xFF0F6B87),
        secondary: Color(0xFF1AA19A),
        tertiary: Color(0xFF14354A),
        appBarStart: Color(0xFF163E56),
        appBarEnd: Color(0xFF0F6B87),
        drawerStart: Color(0xFF12364B),
        drawerEnd: Color(0xFF0E6B73),
        backgroundTop: Color(0xFFE6F5F8),
        backgroundMiddle: Color(0xFFF3FBFB),
        backgroundBottom: Color(0xFFEAF3F7),
        glowA: Color(0x331AA19A),
        glowB: Color(0x221A6F9A),
        glowC: Color(0x2614364B),
        watermarkTitle: 'VENTAS',
        watermarkSubtitle: 'Experiencia comercial clara y confiable',
      );
    case AppRole.tecnico:
      return const RoleBranding(
        role: AppRole.tecnico,
        departmentName: 'Departamento Tecnico',
        departmentAccentLabel: 'Operacion precisa y seguimiento en campo',
        primary: Color(0xFF215B86),
        secondary: Color(0xFF3B8FC2),
        tertiary: Color(0xFF102C42),
        appBarStart: Color(0xFF15364D),
        appBarEnd: Color(0xFF215B86),
        drawerStart: Color(0xFF112E44),
        drawerEnd: Color(0xFF1C5F7E),
        backgroundTop: Color(0xFFE8F1F8),
        backgroundMiddle: Color(0xFFF5F9FC),
        backgroundBottom: Color(0xFFEAF1F6),
        glowA: Color(0x333B8FC2),
        glowB: Color(0x22215B86),
        glowC: Color(0x24102C42),
        watermarkTitle: 'TECNICO',
        watermarkSubtitle: 'Ritmo estable para trabajo de alto enfoque',
      );
    case AppRole.admin:
    case AppRole.asistente:
      return const RoleBranding(
        role: AppRole.admin,
        departmentName: 'Departamento de Administracion',
        departmentAccentLabel: 'Control, coordinacion y vision operativa',
        primary: Color(0xFF0E7490),
        secondary: Color(0xFF1496A8),
        tertiary: Color(0xFF12354B),
        appBarStart: Color(0xFF163D53),
        appBarEnd: Color(0xFF0E7490),
        drawerStart: Color(0xFF13354A),
        drawerEnd: Color(0xFF0D6477),
        backgroundTop: Color(0xFFE7F5F8),
        backgroundMiddle: Color(0xFFF6FBFC),
        backgroundBottom: Color(0xFFEAF2F7),
        glowA: Color(0x331496A8),
        glowB: Color(0x220E7490),
        glowC: Color(0x2612354B),
        watermarkTitle: 'ADMINISTRACION',
        watermarkSubtitle: 'Calma visual para decisiones y supervision',
      );
    case AppRole.marketing:
      return const RoleBranding(
        role: AppRole.marketing,
        departmentName: 'Departamento de Marketing',
        departmentAccentLabel: 'Comunicacion, marca y presencia digital',
        primary: Color(0xFF176B69),
        secondary: Color(0xFF2E9A90),
        tertiary: Color(0xFF173949),
        appBarStart: Color(0xFF1A4150),
        appBarEnd: Color(0xFF176B69),
        drawerStart: Color(0xFF163847),
        drawerEnd: Color(0xFF1A7067),
        backgroundTop: Color(0xFFE8F6F3),
        backgroundMiddle: Color(0xFFF7FCFB),
        backgroundBottom: Color(0xFFEAF3F4),
        glowA: Color(0x332E9A90),
        glowB: Color(0x22176B69),
        glowC: Color(0x24173949),
        watermarkTitle: 'MARKETING',
        watermarkSubtitle: 'Un lenguaje visual sereno y contemporaneo',
      );
    case AppRole.unknown:
      return const RoleBranding(
        role: AppRole.unknown,
        departmentName: 'Espacio de trabajo FullTech',
        departmentAccentLabel: 'Experiencia general de trabajo',
        primary: Color(0xFF1A5C7A),
        secondary: Color(0xFF3484A5),
        tertiary: Color(0xFF163247),
        appBarStart: Color(0xFF173B52),
        appBarEnd: Color(0xFF1A5C7A),
        drawerStart: Color(0xFF143248),
        drawerEnd: Color(0xFF195A73),
        backgroundTop: Color(0xFFE8F2F7),
        backgroundMiddle: Color(0xFFF7FBFD),
        backgroundBottom: Color(0xFFEAF1F6),
        glowA: Color(0x333484A5),
        glowB: Color(0x221A5C7A),
        glowC: Color(0x24163247),
        watermarkTitle: 'FULLTECH',
        watermarkSubtitle: 'Tecnologia confiable, moderna y amable',
      );
  }
}
