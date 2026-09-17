import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';

/// SSL pinning por hash SHA-256 do SPKI (chave pública), não do certificado inteiro.
///
/// Pinar o certificado quebra a cada renovação (90 dias com Let's Encrypt).
/// Pinar o SPKI sobrevive à renovação, porque a chave pública é preservada — só
/// quebra numa troca real de chave, que é justamente o evento que queremos detectar.
///
/// **Escopo (limitação real, não omissão):**
/// este pinning cobre APENAS os domínios próprios — CDN de vídeo e APIs do produto.
/// Os SDKs do Firebase usam a própria pilha de rede (gRPC/Cronet) e não expõem
/// TrustManager configurável. Pinar `*.googleapis.com` é inviável e, se fosse
/// possível, derrubaria o app na primeira rotação de certificado do Google.
///
/// A defesa contra MitM no tráfego Firebase é outra, e está em
/// `docs/05-seguranca-mobile.md`: App Check enforce + trust-anchors apenas do sistema
/// (Android) + ATS com Certificate Transparency (iOS). Ver docs/00-CORRECOES.md C5.
class PinningService {
  PinningService({required this.pins})
      : assert(pins.length >= 2, 'pin primário + backup obrigatórios');

  /// Base64 do SHA-256 do SubjectPublicKeyInfo em DER.
  /// DOIS pins no mínimo: primário (chave em uso) e backup (próxima chave, já gerada
  /// e guardada offline). Com um pin só, perder a chave = app morto até nova release.
  final List<String> pins;

  void apply(Dio dio) {
    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final client =
          HttpClient(context: SecurityContext(withTrustedRoots: true));
      client.badCertificateCallback =
          (_, __, ___) => false; // nunca aceitar cert inválido
      return client;
    };

    adapter.validateCertificate = (cert, host, port) {
      if (cert == null) return false;
      final spki = _extractSpkiSha256(cert.der);
      return spki != null && pins.contains(spki);
    };

    dio.httpClientAdapter = adapter;
  }

  /// Extrai o SPKI do certificado DER e devolve o SHA-256 em base64.
  ///
  /// Implementação: parser ASN.1 mínimo. O SPKI é o 7º elemento do TBSCertificate
  /// (ou 6º em certificados sem `version`). Dart não expõe a chave pública de um
  /// [X509Certificate], então o parse é inevitável.
  ///
  /// Em produção esta função vem de um pacote testado; aqui ela é explícita para
  /// deixar claro o que está sendo pinado. Testada em test/security/spki_test.dart.
  static String? _extractSpkiSha256(Uint8List der) {
    try {
      final spki = _Asn1.findSpki(der);
      if (spki == null) return null;
      return base64Encode(sha256.convert(spki).bytes);
    } catch (_) {
      return null; // parse falhou => trata como não-pinado => conexão recusada
    }
  }
}

/// Parser ASN.1 DER suficiente para localizar o SubjectPublicKeyInfo.
class _Asn1 {
  static ({int start, int len, int contentStart}) _header(Uint8List b, int i) {
    final start = i;
    i++; // tag
    var len = b[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | b[i++];
      }
    }
    return (start: start, len: len, contentStart: i);
  }

  /// Certificate ::= SEQ { tbsCertificate SEQ { ... subjectPublicKeyInfo SEQ } }
  static Uint8List? findSpki(Uint8List der) {
    final cert = _header(der, 0);
    final tbs = _header(der, cert.contentStart);

    var i = tbs.contentStart;
    final end = tbs.contentStart + tbs.len;
    var index = 0;

    while (i < end) {
      final f = _header(der, i);
      final isExplicitVersion = der[f.start] == 0xA0;
      // Campos do TBS: [0] version?, serialNumber, signature, issuer, validity,
      // subject, subjectPublicKeyInfo. O SPKI é o 6º campo depois do version opcional.
      if (!isExplicitVersion) index++;
      if (index == 6 && der[f.start] == 0x30) {
        return Uint8List.sublistView(der, f.start, f.contentStart + f.len);
      }
      i = f.contentStart + f.len;
    }
    return null;
  }
}
