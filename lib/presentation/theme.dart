import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de design do Shield Ack.
///
/// Ideia condutora: o nome do produto é um handshake TCP, e a interface lê a
/// trilha como um **trace de pacotes**. Por isso a cor aqui não decora — ela
/// codifica ESTADO DE PROTOCOLO, e o mesmo hue significa a mesma coisa em
/// qualquer tela: trilha, duelo, quiz, ranking.
///
/// Fundo azul-tinta (não um preto disfarçado) para fugir do clichê
/// "terminal verde sobre preto", que é o default previsível deste segmento.
abstract final class Shade {
  /// Fundo. Azul de verdade — a 12% de luminância ainda lê como azul, não preto.
  static const base = Color(0xFF101A2B);

  /// Superfície elevada (cartões, folhas, campos).
  static const surface = Color(0xFF17243A);

  /// Superfície pressionada / bem sutil.
  static const surfaceLow = Color(0xFF141E31);

  /// Régua do trace, divisores, contornos.
  static const rule = Color(0xFF243350);

  static const text = Color(0xFFE8EEF7);
  static const textDim = Color(0xFF8FA2BE);
  static const textFaint = Color(0xFF5A6B85);
}

/// Estado de um segmento no trace. É a única fonte de cor semântica do app.
enum Wire {
  /// Handshake completo: lição concluída, duelo vencido, resposta certa.
  ack(Color(0xFF3FD0C9)),

  /// Enviado, aguardando: lição em andamento, convite pendente, sua vez.
  syn(Color(0xFFF2B138)),

  /// Reset: errou, expirou, sem vidas.
  rst(Color(0xFFE0616B)),

  /// Ainda não alcançado.
  idle(Shade.textFaint);

  const Wire(this.color);
  final Color color;
}

abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
}

/// Escala tipográfica.
///
/// Space Grotesk na interface: técnica, com desenho um pouco estranho nos
/// números e no "g" — personalidade sem virar display. JetBrains Mono aparece
/// SÓ onde há comando, campo de pacote ou dado real; nunca em rótulo de UI,
/// que é onde a monoespaçada vira maneirismo.
abstract final class Face {
  static TextStyle get display => GoogleFonts.spaceGrotesk(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: Shade.text,
      );
  static TextStyle get title => GoogleFonts.spaceGrotesk(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: Shade.text,
      );
  static TextStyle get body => GoogleFonts.spaceGrotesk(
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: Shade.text,
      );
  static TextStyle get meta => GoogleFonts.spaceGrotesk(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: Shade.textDim,
      );

  /// Números que se alinham em coluna (ranking, placar, XP).
  static TextStyle get figure => GoogleFonts.spaceGrotesk(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Shade.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Apenas conteúdo real de terminal / protocolo.
  static TextStyle get code => GoogleFonts.jetBrainsMono(
        fontSize: 14,
        height: 1.5,
        color: Shade.text,
      );
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Shade.base,
    colorScheme: base.colorScheme.copyWith(
      surface: Shade.base,
      primary: Wire.ack.color,
      onPrimary: Shade.base,
      error: Wire.rst.color,
    ),
    textTheme:
        base.textTheme.apply(fontFamily: GoogleFonts.spaceGrotesk().fontFamily),
    appBarTheme: AppBarTheme(
      backgroundColor: Shade.base,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: Face.title,
      iconTheme: const IconThemeData(color: Shade.textDim),
    ),
    dividerTheme:
        const DividerThemeData(color: Shade.rule, thickness: 1, space: 1),
    splashFactory: InkSparkle.splashFactory,
  );
}
