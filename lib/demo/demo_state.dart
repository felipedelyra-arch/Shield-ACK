import 'package:flutter/foundation.dart';

import '../presentation/theme.dart';

/// Estado da demonstração.
///
/// Existe por um motivo específico: sem `flutterfire configure`, o app não sobe
/// e não dá para olhar a interface no aparelho. Este modo troca o backend por
/// dados em memória e NADA MAIS — as mesmas telas, os mesmos widgets, o mesmo
/// fluxo. Nenhuma tela sabe que está em demo.
///
/// O que ele deliberadamente NÃO simula: correção de quiz no servidor. Aqui o
/// gabarito vive no cliente, o que em produção seria a falha mais grave possível.
/// Por isso o modo é isolado em lib/demo/ e barrado no build de release
/// (ver assert em main.dart).
class DemoState extends ChangeNotifier {
  int xp = 340;
  int level = 4;
  int streak = 7;
  int hearts = 4;
  String displayName = 'Felipe';
  String friendCode = 'K7QM3XZP';

  final tracks = <DemoTrack>[
    DemoTrack('Redes', 'Do quadro Ethernet ao handshake TCP.', [
      DemoLesson('Modelo OSI na prática', 504, 40, Wire.ack, 1.0),
      DemoLesson('Handshake TCP: SYN, SYN-ACK, ACK', 662, 40, Wire.ack, 1.0),
      DemoLesson('Portas, sockets e serviços', 738, 40, Wire.syn, 0.34),
      DemoLesson('Subredes e CIDR', 810, 50, Wire.idle, 0),
      DemoLesson('NAT e port forwarding', 595, 50, Wire.idle, 0),
    ]),
    DemoTrack(
        'Fundamentos de segurança', 'Superfície de ataque e como reduzi-la.', [
      DemoLesson('Tríade CIA sem decoreba', 420, 30, Wire.ack, 1.0),
      DemoLesson('Autenticação vs autorização', 505, 40, Wire.rst, 0.5),
      DemoLesson(
          'Hashing: por que não SHA-256 em senha', 690, 50, Wire.idle, 0),
      DemoLesson('TLS 1.3 e o que o cadeado não diz', 880, 50, Wire.idle, 0),
    ]),
    DemoTrack('DevSecOps', 'Segurança que roda no pipeline, não na reunião.', [
      DemoLesson('Segredos fora do repositório', 460, 40, Wire.idle, 0),
      DemoLesson('SAST, DAST e SCA: quando cada um', 720, 50, Wire.idle, 0),
      DemoLesson('Assinatura e proveniência de build', 640, 50, Wire.idle, 0),
    ]),
  ];

  final friends = <DemoFriend>[
    DemoFriend('Marina', 1820, 21, true),
    DemoFriend('Você', 340, 7, false),
    DemoFriend('Caio', 295, 3, false),
    DemoFriend('Júlia', 160, 1, true),
  ];

  final duels = <DemoDuel>[
    DemoDuel('Marina', 'Redes', DuelTurn.yours, 30, 20, 3),
    DemoDuel('Caio', 'Fundamentos de segurança', DuelTurn.theirs, 10, 10, 2),
    DemoDuel('Júlia', 'Redes', DuelTurn.invite, 0, 0, 0),
  ];

  /// Posição assistida; só avança, como `syncWatchProgress` no servidor.
  void recordWatch(DemoLesson lesson, int positionSec) {
    final p = positionSec / lesson.durationSec;
    if (p > lesson.progress) lesson.progress = p.clamp(0, 1);
    notifyListeners();
  }

  /// Aplica o resultado de um quiz. Em produção isto é a resposta de
  /// `submitQuiz` — aqui só mexe nos mesmos campos que a Callable mexeria.
  void applyQuiz(
      {required DemoLesson lesson, required int correct, required int total}) {
    final passed = correct / total >= 0.7;
    if (passed) {
      lesson.state = Wire.ack;
      lesson.progress = 1.0;
      xp += lesson.xpReward +
          (correct == total ? (lesson.xpReward * .25).round() : 0);
      level = 1 + (xp / 120).floor();
      final list = tracks.expand((t) => t.lessons).toList();
      final i = list.indexOf(lesson);
      if (i >= 0 && i + 1 < list.length && list[i + 1].state == Wire.idle) {
        list[i + 1].state = Wire.syn;
      }
    } else {
      lesson.state = Wire.rst;
      hearts = (hearts - 1).clamp(0, 5);
    }
    notifyListeners();
  }
}

class DemoTrack {
  DemoTrack(this.title, this.blurb, this.lessons);
  final String title;
  final String blurb;
  final List<DemoLesson> lessons;

  int get done => lessons.where((l) => l.state == Wire.ack).length;
}

class DemoLesson {
  DemoLesson(
      this.title, this.durationSec, this.xpReward, this.state, this.progress);
  final String title;
  final int durationSec;
  final int xpReward;
  Wire state;
  double progress;

  bool get locked => state == Wire.idle;

  /// Posição salva, derivada do progresso — é o "parou em 4:12" da trilha.
  int get resumeAtSec => (durationSec * progress).round();
}

class DemoFriend {
  DemoFriend(this.name, this.xp, this.streak, this.online);
  final String name;
  final int xp;
  final int streak;
  final bool online;
  bool get isMe => name == 'Você';
}

enum DuelTurn { yours, theirs, invite }

class DemoDuel {
  DemoDuel(this.opponent, this.track, this.turn, this.myScore, this.theirScore,
      this.round);
  final String opponent;
  final String track;
  final DuelTurn turn;
  int myScore;
  int theirScore;
  int round;
}

/// Questões da demo. O gabarito só está aqui porque é demo — em produção ele
/// vive em `answerKeys/{qId}`, inacessível por Security Rules.
class DemoQuestion {
  const DemoQuestion(this.prompt, this.options, this.correct, this.explanation,
      {this.code});
  final String prompt;
  final List<String> options;
  final int correct;
  final String explanation;

  /// Trecho de terminal/protocolo mostrado acima da pergunta, quando existe.
  final String? code;
}

const demoQuestions = <DemoQuestion>[
  DemoQuestion(
    'O cliente acabou de enviar este segmento. O que o servidor responde?',
    ['SYN', 'SYN-ACK', 'ACK', 'RST'],
    1,
    'O servidor confirma o SYN recebido e envia o próprio SYN na mesma resposta — '
        'daí o nome SYN-ACK. O handshake fecha quando o cliente devolve o ACK final.',
    code:
        'Flags [S], seq 3829471028, win 64240\n  options [mss 1460,sackOK,TS]',
  ),
  DemoQuestion(
    'Uma porta responde com RST imediatamente. O que isso indica?',
    [
      'A porta está aberta e aceitando conexões',
      'Há um firewall descartando o pacote em silêncio',
      'A porta está fechada, mas o host está vivo',
      'O host está fora do ar',
    ],
    2,
    'RST é uma recusa ativa: alguém está lá para responder. Firewall que dropa não '
        'responde nada — é o timeout que denuncia filtragem, não o RST.',
  ),
  DemoQuestion(
    'Qual destes NÃO deve ser usado para armazenar senha de usuário?',
    ['Argon2id', 'bcrypt com custo 12', 'SHA-256', 'scrypt'],
    2,
    'SHA-256 é rápido de propósito, e velocidade é exatamente o que o atacante quer '
        'num ataque de dicionário. Senha pede função lenta e com custo ajustável.',
  ),
];
