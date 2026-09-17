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
  /// Fundo. Azul de verdade — a 9% de luminância ainda lê como azul, não preto.
  static const base = Color(0xFF0D1628);

  /// Superfície pressionada / bem sutil.
  static const surfaceLow = Color(0xFF111D33);

  /// Superfície elevada (cartões, folhas, campos).
  static const surface = Color(0xFF16253F);

  /// Um degrau acima: o cartão em foco da tela (ex.: "Continuar").
  static const raised = Color(0xFF1D2F4F);

  /// Régua do trace, divisores, contornos.
  static const rule = Color(0xFF263A5E);

  static const text = Color(0xFFEAF1FB);
  static const textDim = Color(0xFF93A6C4);
  static const textFaint = Color(0xFF5B6E8C);
}

/// Estado de um segmento no trace. É a única fonte de cor semântica do app.
enum Wire {
  /// Handshake completo: lição concluída, XP, resposta certa.
  ack(Color(0xFF34E0CF)),

  /// Enviado, aguardando: lição em andamento, sequência de dias, sua vez.
  syn(Color(0xFFFFB84D)),

  /// Reset: errou, expirou, vidas.
  rst(Color(0xFFFF6B78)),

  /// Ainda não alcançado.
  idle(Shade.textFaint);

  const Wire(this.color);
  final Color color;

  /// Brilho da cor de estado. Só em elemento que carrega estado — nunca decoração.
  List<BoxShadow> glow([double strength = 1]) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35 * strength),
          blurRadius: 24 * strength,
          spreadRadius: -4,
        ),
      ];
}

/// Respeita "remover animações" do sistema.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
  /// Só na abertura (login): o nome do produto como imagem.
  static TextStyle get hero => GoogleFonts.spaceGrotesk(
        fontSize: 48,
        height: 1.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -2,
        color: Shade.text,
      );
  static TextStyle get display => GoogleFonts.spaceGrotesk(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
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
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Shade.surface,
      labelStyle: Face.body.copyWith(color: Shade.textDim),
      helperStyle: Face.meta.copyWith(fontSize: 12),
      prefixIconColor: Shade.textFaint,
      suffixIconColor: Shade.textDim,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Wire.ack.color, width: 1.5),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide(color: Shade.rule)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? Shade.raised
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Shade.text : Shade.textDim),
        textStyle: WidgetStatePropertyAll(
            Face.body.copyWith(fontWeight: FontWeight.w600)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Shade.raised,
      contentTextStyle: Face.body,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}
