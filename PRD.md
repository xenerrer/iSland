# iSland — PRD v0.4

Atualizado em 2026-09-30. Estado: M0 a M3 entregues; M4 quase; M5 não iniciado.

## 1. Visão

O notch do Mac vira a superfície de controle dos seus agentes de IA. De relance você sabe o que cada agente está fazendo, qual está parado esperando você, e responde pedidos de permissão sem trocar de janela. Começa pelo **Claude Code**; o protocolo é neutro para receber outros agentes depois.

## 2. Problema e público

- **Problema:** com várias sessões de agente em terminais e janelas diferentes, a atenção se perde. Uma sessão fica parada horas num pedido de permissão e você só percebe ao voltar.
- **Público v1:** você. **Público v2:** devs que usam Claude Code em Mac (com ou sem notch), instalando por DMG.

## 3. Princípios

1. **Nunca atrapalhar o agente.** O hook falha em silêncio e sai com código 0. Sem iSland rodando, tudo funciona como hoje.
2. **Seguro por padrão.** Sem resposta do iSland, o pedido de permissão cai no terminal. `AskUserQuestion` e `ExitPlanMode` nunca são respondidos pelo notch.
3. **Local-first.** Sem rede, sem telemetria. Socket Unix `0600` dentro de uma pasta `0700`.
4. **Reversível.** Instalar e remover os hooks mostra o que muda, faz backup e devolve o arquivo idêntico.
5. **Leve e nativo.** SwiftUI/AppKit, sem dependências externas.
6. **Bonito de verdade.** Liquid Glass, respeitando "reduzir transparência" e "reduzir movimento".

## 4. Escopo

**Dentro da v1:** sessões de Claude Code, estados, tempo de cada turno, selo de modo de permissão, aprovação de permissão (clique e atalhos), focar o app da sessão, visual em vidro, sons opcionais, ocultar em compartilhamento de tela, instalador DMG, menu na barra de menus, pt-BR/en. **Adicionados na v0.3 a pedido:** cartão do que está tocando (capa, título, artista, app, anterior/play-pause/próxima, equalizador na pílula fechada) e cartão da próxima reunião (Calendário do macOS, o que inclui Google Agenda, com botão Entrar para Meet/Zoom/Teams).

**Adicionados na v0.4, a pedido (o usuário tinha que "adivinhar em qual chat estava o trabalho"):** cada linha mostra o **nome do chat** (o título da barra lateral do app Claude) com a pasta pequena embaixo; **clicar abre aquele chat** no app Claude; o cartão de aprovação também diz de qual chat vem o pedido (e o botão "Terminal" vira "No chat" quando o chat é do app Claude); o selo cru `bypass` virou texto claro ("sem pedir permissão", com explicação ao passar o mouse); **engrenagem** no cabeçalho da ilha aberta abre os ajustes, e o ✻ da barra de menus virou opcional (desligado por padrão).

**Ajuste da v0.4:** o notch fechado só informa o que importa. Trabalhando (✻) e esperando você (vermelho) aparecem sempre; ao terminar o último trabalho, uma bolinha verde por ~8 s (`doneGlance`) e depois o notch volta a ser só o notch, sem laterais nem contador. Sessões em repouso não ocupam o notch, e o cabeçalho da ilha aberta também deixou de mostrar o ponto verde (a bolinha de cada linha continua).

**Fora da v1:** shelf, HUD de volume/brilho, Mac App Store, telemetria, mostrar o texto dos seus prompts (privacidade: o notch aparece em compartilhamento de tela), Google Agenda por API própria (exigiria projeto no Google Cloud e verificação de OAuth; o caminho pelo Calendário do macOS não pede nada disso).

## 5. Ciclo de vida da sessão (o "CRUD")

| Operação | Como acontece |
|---|---|
| **Criar** | Evento `SessionStart`, ou o primeiro evento de uma sessão desconhecida |
| **Ler** | Pílula fechada mostra o estado geral; ao passar o mouse, lista de sessões; clicar numa sessão traz o app dela para a frente |
| **Atualizar** | Cada evento muda estado e detalhe; sessões que precisam de você sobem para o topo; eventos atrasados nunca sobrescrevem um estado mais novo |
| **Excluir** | `SessionEnd`; processo do agente encerrado (detectado pelo PID em até 15 s); ou 6 h sem eventos |

## 6. Estados

| Estado | Ícone | Quando |
|---|---|---|
| Trabalhando | **✻ do Claude Code** (· ✢ ✳ ∗ ✻ ✽ e de volta, laranja) | `UserPromptSubmit`, `PreToolUse`, `PostToolUse` |
| Precisa de você | ponto vermelho que respira | `PermissionRequest`, `Notification` |
| Parado | ponto verde | `SessionStart`, `Stop` |

## 7. Arquitetura

```
Claude Code ──hook──▶ island-hook ──socket ~/.island/island.sock──▶ iSland.app ──▶ notch
  (stdin JSON)         │  (uma linha de JSON; PermissionRequest espera a resposta)      │
                       ◀──────────── allow / deny / terminal ◀───────────────────────────┘
```

- `IslandCore` (biblioteca): `AgentEvent` e `PermissionPrompt` (protocolo neutro), `UnixSocket`/`SocketServer`/`Responder`, `ClaudeHook` (**todo o conhecimento do Claude Code fica aqui**), `JSONValue` (leitor que preserva ordem), `HookInstaller`.
- `island-hook`: lê o JSON do hook, traduz, repassa. Nunca falha.
- `iSland` (app): `SessionStore` (regras de estado), `IslandView` (SwiftUI), `NotchShape`, `HoverController` (ponteiro sem permissão), `ApprovalHotkeys` (Carbon, só enquanto há pergunta), `StatusMenu`, `ProcessTree`, `L10n`.
- Nomes de chat (v0.4): `ClaudeDesktop`/`DesktopChatIndex`/`TranscriptTitle` em `IslandCore` (lê os registros do app Claude e o fim do transcript; testado com fixtures), `SessionIdentityResolver` no app (leitura em segundo plano ao aparecer uma sessão, ao abrir a ilha e a cada 5 s com ela aberta), `SessionStore.focusTarget` (o chat, o app hospedeiro ou nada).
- Widgets (v0.3): `NowPlayingManager` (processo filho Perl + `MediaRemoteAdapter.framework`, uma linha de JSON por mudança), `CalendarManager` (EventKit), `Widgets` (junta os dois e diz ao layout quais cartões existem), `WidgetViews` (`MusicCard`, `CalendarCard`, `Equalizer`). A lógica pura fica em `IslandCore` e é testada: `NowPlayingDecoder` (mescla diffs, relógio do progresso) e `Agenda`/`JoinLink` (quais eventos aparecem, "em 12 min", link de reunião).
- Tudo mora em `~/.island` (caminho curto e sem espaços). `ISLAND_HOME` realoca tudo, o que isola os testes.

Fatos do Claude Code 2.1.28x confirmados no binário e em sessões reais: o `PermissionRequest` real **não traz `tool_use_id`**, traz `tool_input.description` e `permission_suggestions` de três tipos (`addRules`, `addDirectories`, `setMode`); o `Notification` de permissão chega 6,0 s depois do pedido, o que indica que o prompt do Claude aparece em paralelo ao cartão; `PermissionRequest` roda **antes** do prompt do terminal; a decisão é `{behavior: allow}` ou `{behavior: deny, message}`; "sempre permitir" é `allow` + `updatedPermissions`; hooks aceitam `async`.

## 8. Roadmap

| Marco | Estado | Entrega |
|---|---|---|
| M0 Núcleo | ✅ | janela, socket, CLI de hook, estados |
| M1 Hooks | ✅ | instalar/remover com backup e merge fiel, helper estável, ordem de eventos, PID, menu com consentimento |
| M2 Aprovação | ✅ | cartão no notch, Permitir/Negar/Sempre/Terminal, contagem regressiva, atalhos ⌥⌘Y/N/T, fila de pedidos |
| M3 Visual | ✅ | forma com "orelhas", vidro Liquid Glass (3 estilos), cabeçalho nas laterais do notch, spinner do Claude, acessibilidade |
| M3.5 Música e agenda | ✅ código e testes; 🟡 falta ver ao vivo | cartões de música e reunião, equalizador na pílula, `.app` de desenvolvimento (`run-bundle.sh`) para poder pedir permissão de Calendário |
| M3.6 Chats por nome | ✅ código e testes; 🟡 falta clicar de verdade | nome do chat, clique abre o chat, selo claro, engrenagem no lugar do ✻ |
| M4 Distribuição | 🟡 | DMG com ícone e "leia primeiro" ✅; Sparkle ❌ (precisa baixar); notarização ❌ (precisa conta Apple) |
| M5 Outros agentes | ⬜ | Codex CLI, Gemini CLI pelo mesmo protocolo |

## 9. Critérios de aceite

| Critério | Estado |
|---|---|
| Com o iSland fechado, o Claude Code funciona idêntico | ✅ testado (hook instantâneo e silencioso) |
| Sessão aparece em < 1 s | ✅ observado com sessões reais |
| Pergunta pendente sobe ao topo e abre o notch sozinho | ✅ visto com um `PermissionRequest` real no desktop do usuário |
| Clicar em Permitir/Negar responde ao Claude Code | ✅ clique humano em teste isolado; ✅ 4 decisões nos testes de ponta a ponta |
| Instalar e remover hooks é reversível | ✅ testes automatizados, incluindo "devolve o arquivo byte a byte" |
| Aguenta rajadas e lixo no socket | ✅ 1500 eventos, 2 MB sem quebra de linha, 200 conexões penduradas, 60 perguntas simultâneas: sem perdas, +1 MB de memória |
| Atalhos globais funcionam | 🟡 registro no sistema ✅; ⬜ tecla ainda não apertada |
| Visual legível sobre fundos claros, escuros e cheios | ✅ autocaptura sobre 3 fundos sintéticos **e** no desktop real do usuário (cartão de aprovação, lista de sessões e pílula fechada) |
| Hover abre e fecha a ilha com o mouse real | ✅ visto no log com o mouse do usuário |
| Cartão respondido por um humano com um `PermissionRequest` real | ✅ 08:31: clique em Permitir, o Claude Code rodou o comando 1,7 s depois; ✅ sem resposta: cai no prompt normal |

## 10. Distribuição por DMG sem licença Apple

**Funciona.** `scripts/package.sh` gera `dist/iSland.app` (assinatura ad-hoc, arm64) e `dist/iSland-<versão>.dmg` com atalho para Applications e `READ ME FIRST.txt` bilíngue. Verificado: Info.plist válido, assinatura íntegra, DMG monta, e o teste de ponta a ponta passa **nos binários empacotados**.

**O custo para quem instala:**
- O Gatekeeper **bloqueia a primeira abertura** (`spctl` responde "rejected"). Caminho: Ajustes do Sistema → Privacidade e Segurança → **Abrir Mesmo Assim**, uma vez. Fontes: [Apple Support](https://support.apple.com/en-us/102445), [Michael Tsai](https://mjtsai.com/blog/2024/07/05/sequoia-removes-gatekeeper-contextual-menu-override/).
- **Permissões do sistema (TCC) zeram a cada atualização**, porque o hash da assinatura ad-hoc muda ([exemplo](https://github.com/pathorsAI/parley/issues/75)). Até a v0.2 o app não pedia nenhuma permissão. **Desde a v0.3 pede Calendário** (só depois de um clique em "Conectar", nunca sozinho), então com assinatura ad-hoc quem atualizar o app verá o pedido de novo. Com Apple Developer isso some, e a assinatura passa a precisar de hardened runtime com a entitlement `com.apple.security.personal-information.calendars`.

**Mitigação testada só no build de desenvolvimento:** assinar com um requisito explícito que cita o app (`designated => identifier "com.lucasschoenherr.island"`) em vez do hash do código; assim o macOS deveria manter a permissão entre recompilações (`scripts/bundle.sh`, `STABLE_REQUIREMENT=1`). Ainda **não** confirmado que o macOS honra isso para a Agenda (o log `calendar access is authorized` logo após uma recompilação confirmaria), e **não adotado no DMG**: lá qualquer app ad-hoc com o mesmo id herdaria as permissões.

**Mitigações:** guia de primeira abertura no DMG e no menu; `xattr -dr com.apple.quarantine` documentado; Sparkle com chave EdDSA para atualizações (a validar com app ad-hoc); com Apple Developer (US$ 99/ano) tudo isso some e `SIGN_IDENTITY` já está parametrizado.

## 11. Riscos e decisões em aberto

- **Espera do hook:** como o `PermissionRequest` roda antes do prompt, o terminal pode atrasar até 20 s quando ninguém responde no notch. Mitigado por contagem regressiva visível, botão Terminal e os atalhos. Configurável no futuro.
- **Vidro em janela inativa:** o macOS desbota controles de vidro em janelas que não são a ativa. O painel nunca é ativo (para não roubar o teclado), então os botões são opacos de propósito; só o corpo da ilha é vidro.
- **API privada, só na música:** o "o que está tocando" usa o MediaRemote, fechado a apps comuns desde o macOS 15.4 e ainda aberto ao `/usr/bin/perl` da Apple, que carrega o `MediaRemoteAdapter` (BSD-3, vendorizado em `ThirdParty/`). Se a Apple fechar essa porta, o cartão de música deixa de aparecer e mais nada muda. Janela acima de tudo continua sendo só `NSPanel` com nível alto, sem SkyLight.
- **Dependência de formato interno do app Claude (v0.4):** o nome do chat e o "abrir este chat" usam os arquivos de sessão do app (`claude-code-sessions/**/local_*.json`) e o link `claude://code/continue?session=local_…`, ambos achados no código do app (v2.16120.0) e **não documentados**. Se mudarem, o efeito é suave: as linhas voltam a mostrar a pasta e o clique volta a só trazer o app para a frente. O id do chat só vira link se tiver exatamente a forma que o app aceita. Custo de leitura controlado: o repositório do app pesa ~57 MB (≈500 KB por chat), então só os primeiros bytes de cada arquivo são lidos, e o registro inteiro só dos chats na tela e quando o arquivo muda.
- **Sem ícone na barra de menus por padrão:** os ajustes (e "Sair") só aparecem pela engrenagem da ilha aberta. Se a ilha não abrir por algum motivo, abrir o app de novo mostra a ilha por 6 s; "Mostrar ícone na barra de menus" religa o ✻.
- **Música depende de um processo filho:** precisa ser encerrado junto com o app (tratado: SIGTERM/SIGINT/SIGHUP saem limpo, e órfãos de um crash são varridos na partida) e a primeira abertura de um app baixado (quarentena) com o framework embutido ainda não foi testada numa conta limpa.
- **Google Agenda só aparece se a conta Google estiver nos Ajustes do Sistema** (Contas de Internet, com Calendários ligado). O menu ✻ mostra de onde vêm os eventos e atalha para lá.
- **Sem Xcode:** `@State` e outras macros do SwiftUI não compilam só com as Command Line Tools. Contornado (`ObservableObject`, `phaseAnimator`). Sem Preview do SwiftUI.
- **Ferramenta de captura de dev** (`--selfshot`): usa `CGWindowListCreateImage` (marcada como indisponível no SDK, existe em runtime). Só vê as janelas do próprio app, mas o macOS pergunta se o app que a lançou pode gravar a tela. É ferramenta de desenvolvimento, não vai no produto.
- **Hooks órfãos:** se o helper for apagado com os hooks ainda registrados, o Claude Code registra erro a cada ferramenta. O menu "Remover hooks" é o caminho certo antes de apagar o app.
- **Bundle ID** `com.lucasschoenherr.island` aprovado como provisório; trocar depois zera permissões de quem já instalou.
- **Licença** do iSland: a definir (código do zero, sem GPL).

## Vários monitores
Padrão: ilha na tela principal; opção de todas as telas ou uma específica. Ícones ocultos em vídeo em tela cheia por padrão (por tela).
