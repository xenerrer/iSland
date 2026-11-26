# iSland — segurança

## Modelo de ameaças
O iSland roda como o usuário, sem rede, e conversa com os agentes (Claude Code, Codex, Gemini) por um socket Unix local.

| Ativo | Ameaça | Mitigação |
|---|---|---|
| Aprovação de comandos | Outro processo/usuário forja um pedido ou responde por você | Socket `~/.island/island.sock` 0600 em pasta 0700, `umask` restrito, checagem do dono do par (`getpeereid`), limite de 160 conexões, timeout ocioso |
| Aprovação de comandos | Texto enorme/enganoso escondendo o que será executado | Texto sanitizado (caracteres de controle/bidi viram ⍰ visível); o cartão rola, então comandos longos podem ser lidos até o fim e aprovados; só acima de 8000 caracteres (`needsReview`) o "Permitir" some e a decisão vai para o terminal |
| Arquivos de config dos agentes | Corrupção ao instalar/remover hooks | Backup antes de editar, escrita atômica, remoção só das nossas entradas |
| Logs | Vazar nomes de ferramentas e mensagens | `~/.island/app.log` 0600 |
| Música | Código de terceiros | Adapter fixado por checksum (`ThirdParty/.../CHECKSUMS.txt`, verificado no `check.sh`), processo filho com ambiente limpo, só frameworks da Apple |
| Links | Abrir URLs arbitrárias | Só hosts permitidos (reuniões) e `claude://` com id validado |
| Câmera/Fotos/Agenda | Uso indevido | Permissão inline, câmera só com o espelho aberto, nada gravado/enviado, fotos só na pasta Imagens após consentimento |
| Rede | Exfiltração | O app não abre conexões (verificado: 0 conexões) |

| Histórico de projetos | Revelar o que você estava fazendo | `~/.island/recent.json` 0600 (pasta 0700): só nome da pasta, caminho, título do chat e hora; sem conteúdo de conversa; expira em 48 h; "Esquecer projetos recentes" apaga tudo |
| Notificações | Texto na tela de bloqueio | Só nome do chat, tempo e tipo da pergunta; nunca o comando ou o pedido |

| Prévia do vídeo (opcional) | Capturar a tela além do necessário | Desligada por padrão; precisa da permissão de Gravação de Tela do macOS; captura só a janela do player, em baixa resolução, só enquanto o bloco de música está visível; a imagem fica em memória, nunca é gravada nem enviada |

## Riscos residuais (honestos)
- Build ad-hoc, sem Hardened Runtime nem notarização: o Gatekeeper avisará. **Antes de vender: Developer ID + notarização.**
- Qualquer processo do **mesmo usuário** consegue falar com o socket (inevitável em um socket local; mitigado pelo item de aprovações acima).
- Codex/Gemini: payloads reais não testados; Gemini não tem protocolo de aprovação (só status).
- Sem Sparkle ainda: atualização manual.

## Boas práticas recomendadas daqui pra frente
1. **Assinatura e distribuição**: Developer ID, Hardened Runtime (`--options runtime`, entitlement de calendário/câmera), notarização + staple do DMG; guardar certificados e chaves em cofre com backup.
2. **Atualizações (Sparkle)**: chave EdDSA privada fora do repositório (cofre/Keychain), appcast só por HTTPS, assinar cada release, testar rollback; nunca reutilizar a chave de outro projeto.
3. **Licença (Stripe)**: webhook valida assinatura do Stripe; licença = token assinado (Ed25519) verificado offline; não depender de servidor para o app abrir; nada de telemetria sem opt-in.
4. **Privacidade**: política em LGPD (o que lê: títulos/horários da agenda, texto de pedidos dos agentes; nada sai do Mac). Canal de contato para vulnerabilidades (`security.txt`, divulgação responsável).
5. **Cadeia de suprimentos**: dependências fixas por versão/checksum, SBOM por release, build reproduzível em CI, `check.sh` obrigatório antes de qualquer release.
6. **Engenharia**: revisão de código em toda mudança, fuzz do parser JSON e do socket (já há stress de 1500 eventos), teste em conta limpa do macOS, crash reports sem PII.
7. **Resposta a incidentes**: plano de revogar chave/atualização, versão mínima suportada, aviso aos clientes.
