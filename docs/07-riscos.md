# 7. Riscos residuais conhecidos

Riscos **aceitos**, não esquecidos. Cada um tem gatilho de reavaliação.

| # | Risco | Por que aceitamos | Mitigação atual | Reavaliar quando |
|---|---|---|---|---|
| R1 | **Redistribuição de vídeo dentro da janela de 120s.** O token não é vinculado criptograficamente ao uid (C6). | DRM (Widevine L1 / FairPlay) custa licença + integração e não cabe no MVP. | TTL 120s, rate limit 20/10min, `auditLogs` correlacionando emissões por uid. | Sinal de conta compartilhada em escala, ou conteúdo pago |
| R2 | **Cache do Firestore não é criptografado no disco.** O SDK não oferece opção. | Nosso banco local é cifrado; o cache do Firestore guarda catálogo e progresso — não credenciais. | `cacheSizeBytes` limitado a 40MB, `allowBackup=false`, PII apenas em `/private`, wipe no logout. | Se algum dado sensível precisar ir para coleção cacheada |
| R3 | **Detecção local de root/hook é contornável.** Por definição: o atacante controla o processo. | É telemetria e degradação, não controle de acesso. O controle é o App Check. | Política graduada; App Check enforce no backend. | Nunca — é limitação estrutural, não bug |
| R4 | **Sem replay protection de token do App Check.** `consumeAppCheckToken: false`. | Tokens de uso único exigem round-trip extra por chamada e degradam o p95 do caminho crítico. | Rate limit por uid, idempotência no servidor, TTL curto do token. | Se surgir abuso automatizado com token válido |
| R5 | **`watchedSec` pode inflar em reenvio de lote.** É métrica, não dinheiro. | Um ack por item de heartbeat custaria mais writes do que o dado vale. | `lastPositionSec` é monotônico e correto; só `watchedSec` é aproximado. | Se watch-time virar base de cobrança ou certificação |
| R6 | **BGTaskScheduler no iOS pode nunca rodar.** O SO decide. | Limitação da plataforma. | Drenagem no `resume` é o caminho principal; background é reforço. | — |
| R7 | **`clientElapsedMs` é declarado pelo cliente.** | Não influencia a nota, só a auditoria. | Piso de 1,2s/questão + `auditLogs`; nota vem do servidor. | Se o anti-cheat precisar de precisão, medir no servidor entre `startLesson` e `submitQuiz` |
| R8 | **`buildLeaderboard` a cada 15 min não é tempo real.** | Ranking ao vivo é impossível no Firestore (sem `ORDER BY SUM()`). | Delay comunicado na UI ("atualizado há X min"). | Ligas ao vivo entrarem no escopo |
| R9 | **Documento agregado `catalog` tem teto de 1 MB.** | Cabe ~500 lições com folga. | Alerta no `publishCatalog` se passar de 700 KB. | Catálogo passar de ~400 lições |
| R10 | **Um cliente comprometido pode enfileirar submissões offline e despejá-las de uma vez.** | Nenhuma fila do lado do cliente resolve isso. | Rate limit no servidor barra o despejo; `auditLogs` registra o padrão. | Se surgir farming de XP em escala |
| R11 | **freeRASP envia telemetria para a Talsec** (terceiro) e exige registro. | Trade-off aceito: construir detecção equivalente internamente custa mais do que vale. | Documentado na política de privacidade; sem PII no payload. | Se a política de privacidade B2B proibir terceiros |
| R12 | **`email_verified` não protege recursos de aprendizado.** Decisão de produto (C8). | Bloquear aprender por verificação de e-mail mata a ativação. | Só recursos sociais exigem verificação. | — |

---

## Ameaças fora do modelo (explicitamente não tratadas)

- **Captura por câmera externa.** Nenhum controle de software resolve.
- **Engenharia reversa do binário.** Ofuscação eleva o custo; não impede.
  A premissa é que o atacante **vai** ler o cliente — por isso nada sensível está nele.
- **Conta legítima compartilhada entre pessoas.** Detectável por `auditLogs`,
  não bloqueado no MVP.
- **Ataque de canal lateral no Keystore / device comprometido em nível de kernel.**
  Fora do alcance de um app.
