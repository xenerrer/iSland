# iSland — revisão da manhã

## Atualização de 2 de outubro (noite): outros agentes, primeira abertura guiada, Macs sem notch

- **Agenda:** voltei ao cartão de antes (sem a coluna e sem o mês). Agora dá para **rolar para cima e para baixo dentro do cartão** para ver o resto do dia, um evento por vez; ele abre no que está acontecendo ou no próximo, e "3/5" mostra onde você está. Conferi na janela real que ele abre no evento certo; a rolagem em si precisa da sua mão.
- **Animação:** o padrão agora segue o jeito da Apple (mola suave, quique mínimo ao abrir e nenhum ao fechar, conteúdo entra saindo de um leve desfoque). O estilo elástico do boring.notch ficou como opção em *Animação* no menu.
- **Outros agentes (Codex CLI e Gemini CLI):** o mesmo helper atende os três (`island-hook --agent …`). Cada um tem o seu "pensando": **Claude** ✻ florescendo, **Gemini** pontinhos braille azuis, **Codex** um ponto • que pulsa (o que o terminal de cada um mostra, segundo a documentação e o código deles). Codex: status e aprovação de permissões, igual ao Claude (o Codex pede que você confie nos hooks novos uma vez com `/hooks`). Gemini: só status (os hooks dele não têm protocolo de aprovação confiável); um pedido de permissão deixa a linha vermelha. **Escrito pela documentação e testado com payloads no formato dela; você não tem os dois instalados, então não foi testado com os programas de verdade.** Aparecem no menu só se parecerem instalados.
- **Primeira abertura guiada:** janela com boas-vindas, conectar agentes, agenda, espelho/fotos e dicas. Abre sozinha na primeira vez (**inclusive no seu Mac, uma vez, no próximo relançamento**) e fica em *Primeiros passos…* no menu.
- **Macs sem notch:** notch virtual da altura da barra de menus; fechado e sem nada a mostrar fica invisível, e o topo central ainda abre a ilha.
- **Vídeo em tela cheia:** com YouTube, Netflix ou qualquer player em tela cheia **e mídia tocando**, o notch fechado esconde os ícones e eles voltam ao sair. Detecta uma janela de outro app cobrindo a tela inteira (janela maximizada não conta), então o app Claude em tela cheia sem mídia **não** esconde. Pergunta de permissão ainda abre a ilha. Liga/desliga em *Esconder em vídeo em tela cheia*. O log mostra `another app is in full screen`. Não testei com um vídeo de verdade.
- **boringNotch original:** encerrado e retirado dos itens de login (o app continua instalado).
- **Atualização automática (Sparkle):** ver a resposta no chat; não implementei porque precisa de decisões suas (conta Apple, servidor, chaves).
- 174 testes passam. Não conferido na tela: a rolagem do cartão, a janela do guia, os spinners de Codex/Gemini em movimento.

---

## Atualização de 2 de outubro (fim da tarde): agenda numa coluna à direita

- Com a ilha aberta, a **agenda ocupa uma coluna só dela, à direita** (a esquerda segue com chats, pomodoro e música). Mostra o **dia** (dia inteiro primeiro, o que acontece agora em laranja, os que já passaram apagados, **Entrar** e espelho nas reuniões com link) ou o **mês** (grade com um pontinho por calendário em cada dia; toque num dia para ver os eventos). Setas mudam dia/mês, o título volta para hoje, o botão pequeno alterna dia/mês (fica salvo). Sem permissão, a coluna mostra o botão Conectar.
- Quando chega um pedido de permissão, a ilha volta à largura de antes, para o cartão ter a atenção toda.
- **Corrigido:** o alerta "salvar fotos em Imagens" (e os outros alertas do app) abria **embaixo** do notch, que engolia os cliques. Agora todo alerta abre um nível acima da ilha.
- **Não conferido na tela real:** a coluna da direita com vidro e o alerta acima do notch.

---

## Atualização de 2 de outubro (tarde): pomodoro configurável, notch equilibrado, animação do original

- **Pomodoro (versão final do visual):** no notch fechado fica só um **anel pequeno com sempre 30 bolinhas** (qualquer duração; cada uma vale 1/30 da fase), que vão se apagando no sentido horário a partir do topo; branco no foco, verde na pausa. O tempo exato e pausar/pular/parar estão no cartão da ilha aberta. O ícone do cabeçalho é um cronômetro; clicar abre a configuração e inicia, e com ele rodando pausa/continua.
- **Equilíbrio no notch fechado:** tudo que aparece (contador, equalizador, tomate+tempo, círculo, status) é dividido com a **mesma quantidade em cada lado** (4 itens = 2 e 2) e as duas laterais têm a mesma largura, então a pílula fica centrada.
- **Selo "sem pedir permissão":** agora só o ícone cinza; o texto fica no tooltip.
- **Animação:** copiei o jeito do boringNotch original: abre com um leve quique, fecha sem quicar, e o conteúdo cresce de cima (escala 0,8 + fade). **Tempo para abrir** configurável no menu (instantâneo, 120 ms padrão, 300, 500, 800 ms, 1,2 s).
- 153 testes passam. Não conferido na tela: a animação (só você sente) e o notch real com 4 itens.

---

## Atualização de 2 de outubro: pomodoro de verdade e selo discreto

- **Pomodoro:** o tomate 🍅 no cabeçalho da ilha inicia (antes só existia no menu da engrenagem, por isso você não achou). 25 min de foco, 5 de pausa, e 15 de pausa longa a cada quarto foco; *Pomodoro 50 / 10* fica no menu. Ao lado do notch fechado: o tomate (☕️ na pausa) de um lado e, do outro, um círculo de 30 tracinhos que vão se apagando (vermelho no foco, verde na pausa), com o estado dos agentes no meio. O cartão tem pausar, pular e parar; a pausa começa sozinha e depois dela ele espera você iniciar o próximo foco. Som em cada fim. Enquanto roda, o equalizador da música não aparece no notch fechado.
- **Selo "sem pedir permissão":** sem cor e sem cápsula, só texto cinza pequeno com ícone; a explicação continua ao passar o mouse.
- 150 testes passam. Não conferido na tela: o tomate/círculo no notch real e o som.

---

## Atualização das 15:40 (1º de outubro): as quatro ideias e o vidro sem degradê

- **Vidro sem degradê preto:** no vidro e no vidro claro, o topo da ilha não tem mais a faixa preta que se dissolvia; o vidro mostra o papel de parede até em cima. Continuam a tinta leve e a película que garantem a leitura (se quiser ainda mais transparente, ajusto). Fechado, a pílula segue preta para se fundir ao notch.
- **Ver como estou antes da reunião:** no cartão da agenda, em reuniões com link, há um ícone de pessoa ao lado de **Entrar**. Ele abre o espelho com um botão **Entrar** ali mesmo.
- **Novo chat com um clique:** ícone de lápis no cabeçalho lista as pastas mais recentes; clicar numa abre um chat novo nela, no app Claude (`claude://code/new?folder=…`; o app pode pedir uma confirmação por ser um link externo).
- **Uso do plano: removido.** A primeira versão estimava por tokens e estava errada. A versão com os % reais dependia do login do Claude Code no terminal (o app Claude tem login próprio, que o iSland não toca), que não está ativo no seu Mac, então foi tirada por completo, junto com a leitura do Keychain.
- **Foco (pomodoro):** *Foco: 25 min* e *Foco: 50 min* no menu da engrenagem. Cartão com contagem regressiva e **Parar**; o notch fechado mostra os minutos que faltam; toca um som no fim.
- O contador "N sessões" saiu do cabeçalho para caberem os três ícones (lápis, pessoa, engrenagem).
- 152 testes passam. **Não conferido (precisa de você):** o vidro novo na tela, o lápis abrindo chat novo de verdade, o botão Entrar a partir do espelho e o som do foco.

---

## Atualização das 15:20 (1º de outubro): espelho e botão de remover

- **Espelho:** ao lado da engrenagem há um ícone de pessoa. Clicar liga a câmera e você aparece num círculo pendurado no notch (espelhado, como um espelho de verdade); o botão verde **Voltar** desliga a câmera e devolve a ilha normal. A câmera só fica ligada enquanto o espelho aparece, a imagem não é gravada nem enviada, e, se chegar um pedido de permissão, o cartão de aprovação tem prioridade e a ilha volta ao normal. **O macOS vai pedir acesso à câmera na primeira vez** (só o app instalado pode pedir).
- **Remover:** cada linha tem um **×** no canto direito que tira o chat da lista. Ele volta sozinho quando aquele chat começar algo novo (nova mensagem, pedido de permissão), mas não por "barulho" de um chat parado (fim de turno, lembrete de ocioso).
- 135 testes passam. Conferido: visual dos dois recursos sem câmera (render), e a regra de remoção. **Não conferido:** a câmera de verdade (precisa do seu clique e do pedido do macOS) e o clique no × (precisa da sua mão).

---

## Atualização das 15:15 (1º de outubro): a bolinha verde não fica mais (ajuste da v0.4)

Você pediu que, terminado o trabalho, a bolinha verde não ficasse ali em cima. Agora o notch fechado só mostra o que importa: o **✻** enquanto algo trabalha, o **vermelho** quando algo espera você, e, quando o **último** trabalho termina, uma **bolinha verde por uns 8 segundos** (para você notar que acabou) e depois **nada**: o notch volta a ser só o notch, sem as laterais e sem o contador. Sessões paradas não ocupam mais o notch. Na ilha aberta, o cabeçalho também deixou de mostrar o ponto verde ("Tudo parado" só em texto); a bolinha de **cada linha** continua, porque diz o estado daquele chat.

- Só um término de verdade acende o verde: sessão que ficou muda e foi "assentada", chat fechado ou sessão que nunca rodou não acendem nada. Se outro chat ainda estiver trabalhando, o ✻ continua e o verde espera o último terminar.
- Se preferir **nunca** ver o verde: `defaults write com.lucasschoenherr.island doneGlance 0` (e outro número muda os segundos). Se preferir que fique até você olhar, me diga.
- 130 testes passam (eram 123), 7 deles novos para essa regra. Visual conferido em três estados: logo após terminar, em repouso e a ilha aberta.
- **Experimento para a Agenda:** o app de desenvolvimento agora é assinado com um requisito que cita o app em vez do hash do código. A ideia é o macOS **não esquecer mais a Agenda a cada recompilação**. Você vai precisar clicar em **Conectar** mais uma vez por causa deste relançamento; se o experimento funcionar, na próxima recompilação o log (`~/.island/app.log`) mostra `calendar access is authorized` logo na partida, sem novo clique. Eu aviso o resultado quando houver a próxima recompilação.

---

## Atualização das 15:10 (1º de outubro): chats por nome, clique que abre o chat, engrenagem (v0.4.0)

Seus quatro pontos, um por um:

**1. O que é `bypass`?** É o modo **"Ignorar permissões"** (*bypass permissions*) do Claude Code: nesse chat o Claude executa comandos e edita arquivos **sem pedir a sua aprovação**. Eu mostrava o selo para você saber que, naquela linha, nunca vai aparecer um cartão de Permitir/Negar (ela roda solta). A palavra crua era jargão, e nem estava traduzida. Agora o selo diz **"sem pedir permissão"**, em laranja e com um escudo cortado, e ao passar o mouse sobre ele aparece a explicação inteira. Os outros dois modos ganharam selos neutros: **"edições automáticas"** e **"só planejando"**. O texto está em `L10n.modeBadge` se você quiser outro.

**2. O nome do chat no lugar do nome da pasta.** Cada linha agora mostra o **título que o app Claude exibe na barra lateral**, com a pasta pequena embaixo (com um ícone de pasta). O cartão de aprovação também diz de qual chat vem o pedido. Como funciona: o app guarda um arquivo por chat; eu casei pelo id da sessão que o hook já manda. Com os seus dados reais, **12 das 17 sessões recentes casaram** (todas com título). As 5 restantes não existem no app (4 nem têm histórico em disco) e mostram a pasta, como antes. Um chat iniciado no terminal usa o título gravado no histórico dele, se houver.

**3. Clicar na linha leva ao chat certo.** Uso o link interno do app Claude, `claude://code/continue?session=local_…`, que achei no código do app (não é documentado). Testei o link de verdade com este chat: o Claude passou para a frente sem erro. **Não testei clicando numa linha de outro chat**, para não trocar a sua tela sem avisar; esse é o teste que falta (abra a ilha e clique numa linha de outro chat). Se o link falhar numa versão futura do app, o clique volta ao comportamento antigo (traz o app para a frente). No cartão de aprovação, o botão "Terminal" agora diz **"No chat"** para chats do app Claude, porque devolver o pedido ali significa responder no chat, não num terminal.

**4. Engrenagem.** Ao abrir a ilha, há uma engrenagem no canto direito do cabeçalho; ela abre o mesmo menu de antes (Estilo, Sons, música, agenda, hooks, Sair…). O **✻ da barra de menus sumiu**; continua disponível em *Mostrar ícone na barra de menus*. Se um dia a ilha não abrir, abrir o app de novo (Spotlight ou Finder) mostra a ilha por 6 segundos.

**Verificado sem precisar da sua tela:** 123 testes passam (eram 96), incluindo achar o chat por id de sessão (com título antes e depois do bloco gigante de cada arquivo, arquivo meio escrito, cópia arquivada, título que muda), o fallback pelo histórico, a validação do link e para onde cada clique vai. Com dados reais, este chat resolveu para o registro certo em 43 ms. No app em execução o log mostrou *"chat names updated for 1 of 1 session(s), 1 open in the Claude app"* logo no primeiro evento. O layout foi renderizado em português com os três selos, uma linha sem nome de chat e o cartão de aprovação.

**Não verificado (precisa do seu clique):** clicar numa linha de outro chat; a engrenagem abrindo o menu por cima do painel; os tooltips; e a aparência das linhas novas com o vidro de verdade.

**Atenção, a Agenda pede "Conectar" de novo.** Cada vez que recompilo o app, a assinatura ad-hoc muda e o macOS esquece a permissão da Agenda. Você concedeu às 14:33 e eu recompilei depois, então o cartão voltou a pedir. Um clique em **Conectar** resolve até a próxima compilação. O item K da fila (certificado local autoassinado) acaba com isso de vez; me diga se quer.

---

## Atualização das 13:20 (1º de outubro): música e agenda (v0.3.0)

Você pediu a agenda do Google e o "negócio de saber se tá tocando e o quê". Está feito, e o app que está no ar agora já é a versão nova, rodando como **`.app` de verdade** (`~/iSland/.build/bundle/iSland.app`), que é o que permite o macOS pedir a permissão da Agenda.

**O que você precisa fazer (2 minutos, só você pode):**
1. Passe o mouse no notch. Vai aparecer um cartão **"Mostrar sua agenda aqui"** com o botão **Conectar**. Clique e aceite o pedido do macOS.
2. **Google Agenda:** o iSland lê o app Calendário do macOS, então a conta Google precisa estar em *Ajustes do Sistema → Contas de Internet → Google* com **Calendários** ligado. O menu ✻ mostra de onde vêm os eventos ("Agenda: Google, iCloud…") e, se faltar o Google, oferece **Adicionar conta Google…**.
3. Música não pede nada. Se tiver algo registrado como "Tocando agora" (Spotify, Música, uma aba do YouTube), aparece o cartão ao abrir a ilha e, **enquanto toca**, um equalizador ao lado do notch mesmo fechado. Pausado, o equalizador some e o cartão mostra ⏸ e o botão ▶.

**O que é cada coisa:** o cartão de música mostra capa, título, artista, o app de onde vem ("Google Chrome", "Spotify") e anterior / play-pause / próxima. No YouTube o "artista" é o **canal**. O cartão da agenda mostra o próximo evento (hora, título, "em 12 min", nome da agenda) e um botão **Entrar** quando o evento tem link de Meet, Zoom ou Teams. Os dois somem enquanto há uma pergunta de permissão esperando, para o cartão ter a atenção toda, e podem ser desligados no menu ✻.

**Verificado sem precisar da sua tela:**
- 96 testes passam (eram 88): decodificador do "Tocando agora", regras da agenda, a conta do tamanho da ilha com os cartões. `scripts/check.sh --package` passa inteiro, inclusive o novo passo que confere o adaptador de música **dentro do app empacotado** (já reassinado), o texto da permissão em inglês e português e a assinatura.
- O adaptador leu o "Tocando agora" **real** deste Mac: um vídeo do YouTube no Chrome, **pausado**, com o nome do canal no campo de artista e `com.google.Chrome` como origem. Ou seja, o caso que você descreveu funciona de ponta a ponta até o dado.
- Visual renderizado em português nos três estados (tocando, pausado, só música + agenda) e na pílula fechada, com o equalizador centrado na lateral. O equalizador respeita "Reduzir movimento" (barras paradas).
- Achei e corrigi um problema real: matar o app com `kill`/`pkill` deixava o processo Perl da música órfão. Agora o SIGTERM sai limpo (app, adaptador e socket) e os órfãos de um crash são varridos na partida. Testado nos dois caminhos.

**Não pude verificar (a sua tela está bloqueada e o monitor apagado desde 13:03; não tentei acordar nem desbloquear):**
- O **vidro de verdade** com os cartões (a captura saiu transparente). Os cartões foram vistos só no render sem vidro. Quando você voltar: `scripts/shots.sh /tmp/shots` ou simplesmente olhe o notch.
- O clique em **Conectar**, o pedido do macOS e **eventos reais** da sua agenda (dependem do seu clique).
- Os botões anterior / play-pause / próxima controlando de verdade, e o equalizador na pílula real com algo tocando.
- O app baixado de um DMG (quarentena) carregando o framework de música numa conta limpa.

**Decisões que tomei (diga se discorda):**
- Li "conte" como **conteúdo** (o que está tocando). Se você quis dizer **conta** (por exemplo, qual conta do Spotify), o macOS não informa isso; o cartão mostra o **app** de origem.
- **Google Agenda pelo Calendário do macOS**, e não por API própria do Google: não precisa de chave, de projeto no Google Cloud nem de tela de consentimento, e nada sai do seu Mac. O custo é a conta precisar estar nos Ajustes do Sistema.
- **Música usa uma API privada** (o truque do `/usr/bin/perl`, que o boringNotch também usa). Se a Apple fechar essa porta, só o cartão de música para de aparecer. O código do adaptador (BSD-3) está em `ThirdParty/` com a licença.
- Com assinatura ad-hoc, **cada rebuild vira um app "novo" para o macOS e ele pode pedir a Agenda de novo**. Para instalações de DMG isso acontece a cada atualização. Para o desenvolvimento, ver o item K da fila.
- Versão subiu para **0.3.0**.

---

## Atualização das 08:40 (1º de outubro): o fluxo de aprovação foi provado com o Claude Code de verdade

Os seus dois primeiros testes caíram em sessões `bypassPermissions`, onde o Claude Code não pede nada. Para provocar um pedido real, mudei **esta** sessão para o modo padrão (isso só reduz permissões, então o app não pede aprovação) e, depois do teste, voltei ao `bypass` com a **sua** aprovação no cartão do app.

O que aconteceu, com horários do log:
- **Sem resposta** (2 vezes): o cartão apareceu com os dados reais, ninguém respondeu em 20 s, o log registrou `hook left without an answer` e o Claude Code seguiu com o prompt normal. O "seguro por padrão" funciona na prática.
- **Com o clique em Permitir** (08:31): pedido às 08:31:16.792, ponteiro na ilha às :17.634, `PostToolUse` às :18.464. **O Claude Code aceitou a resposta do cartão e rodou o comando 1,7 s depois do pedido.**

O que aprendi com o pedido real:
- **O `PermissionRequest` real não traz `tool_use_id`** (meus testes e a documentação supunham que sim). Corrigi: um cartão sem esse id agora some quando a ferramenta termina, combinando por sessão e nome da ferramenta.
- O `Notification` de permissão chegou **exatamente 6,0 s** depois do pedido nas duas vezes sem resposta. Isso indica que o prompt do próprio Claude aparece **em paralelo** com o cartão, e não só depois do hook. Ou seja, esperar no cartão não atrasa o prompt normal.
- O pedido traz `tool_input.description` (a explicação do próprio modelo sobre o comando) e sugestões de 3 tipos: `addRules` (às vezes com duas regras, ex.: `Bash` e `Read`), `addDirectories` e `setMode`. O iSland aplica só a primeira `addRules`, como prometido.
- Sessões abertas na pasta pessoal apareciam como `lucasschoenherr`; agora aparecem como `~`.
- 73 testes passam; os scripts de teste usam o formato real.

---

## Atualização das 07:50 (1º de outubro)

- **O app passou a noite inteira no ar**: 9h54 sem nenhum erro, 51 MB de memória. A captura de esquema só pegou os eventos desta conversa, porque ninguém abriu outra sessão; ela traz uma pista útil: o `Stop` real tem os campos `last_assistant_message`, `background_tasks` e `session_crons` (os dois últimos vieram vazios, então ainda não sei o formato dos itens).
- **A gravação de tela foi liberada para o Claude** (item A da fila): o `screencapture` voltou a funcionar. Usei isso **só para ver o notch**, recortando uma faixa de poucos pontos de altura. Uma das capturas pegou, por baixo da ilha, parte do que estava no seu navegador; não usei nem guardei nada daquilo e apaguei todas as imagens da tela real. Se não era a sua intenção, revogue em Ajustes → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema.
- **Verificado no seu desktop real**: o cartão de aprovação (com a dica ⌥⌘Y/⌥⌘N, o que prova que os atalhos foram aceitos pelo sistema), a lista de sessões com vidro sobre o seu fundo, a pílula fechada encaixada no notch físico e o hover com o seu mouse. O pedido de teste foi respondido **Permitir** por você em 3 segundos e o hook imprimiu exatamente o JSON que o Claude Code espera.
- **Novo**: o tempo de cada turno na linha da sessão ("Edit · 1m 20s", "Pronto · 3m 12s"); selo `bypass` nas sessões que nunca pedem permissão (esta aqui é uma, e é por isso que ela nunca gerou um pedido real); no menu ✻, **Sons** e **Ocultar em compartilhamento de tela**, ambos desligados por padrão. 69 testes passam.
- ~~Continua não testado: um `PermissionRequest` real~~ **Testado às 08:31** (ver acima).

---

Escrito na noite de 2026-09-30 (última edição às 21:48), sem você por perto. **Nada aqui foi feito pedindo algo ao sistema além do que você já tinha autorizado** (fechar o boringNotch, editar o `~/.claude/settings.json`, bundle ID provisório). O que dependia de um "sim" seu está na seção 4, com o comando pronto.

## 0. Quatro coisas antes de mexer em qualquer outra

1. **Um diálogo do macOS pode estar aberto na sua tela**: *"Claude deseja ignorar o seletor de janelas privadas do sistema para acessar diretamente a tela e o áudio"*, com os botões "Permitir" e "Abrir Ajustes do Sistema".
   Foi disparado pelos meus testes de captura do visual: o app captura as próprias janelas e, como ele foi lançado pelo app Claude, o macOS pergunta se o **Claude** pode gravar a tela. **Eu não cliquei e não tenho como clicar.**
   - Se você não quer que o Claude possa ver a sua tela: **não clique em Permitir**; é só fechar/ignorar o diálogo.
   - "Permitir" daria ao app Claude acesso à tela inteira, o que me deixaria verificar o visual no seu desktop real. Decisão sua (item A da seção 4).
2. **O boringNotch continua fechado**, como você pediu para os testes. Para reabrir: `open -a boringNotch`. Os dois ocupam o mesmo lugar, então não vale deixar ambos abertos.
3. **O iSland está rodando e os hooks estão instalados** no seu `settings.json`. Se um pedido de permissão do Claude Code demorar uns 20 s para aparecer no terminal, é de propósito: ele espera a sua resposta no notch antes de perguntar no terminal (seção 6, "espera do hook"). Para desligar tudo: seção 7.
4. **Deixei ligada uma captura de *esquema* dos eventos do Claude Code** (arquivo `~/.island/capture-schema`). Ela grava em `~/.island/schema.jsonl` só **nomes e tipos de campos** e uns poucos valores que explicam o protocolo (`notification_type`, `tool_name`...); todo o resto vira `"<string>"`, então nenhum prompt, comando ou caminho seu é gravado (há 4 testes provando a redação). O objetivo é eu ver amanhã os `Notification`/`PermissionRequest` **reais** que aconteceram durante a noite. Leia o arquivo se quiser conferir. Para desligar: `rm ~/.island/capture-schema ~/.island/schema.jsonl`.

## 1. O que mudou desde que você foi dormir

**M2 — aprovar permissões pelo notch.** Um pedido do Claude Code abre o notch sozinho com um cartão: o comando, o projeto, uma contagem regressiva de 20 s e quatro botões — **Negar**, **Terminal** (devolve a pergunta ao terminal), **Sempre** (aplica a regra que o próprio Claude sugere, só a primeira) e **Permitir**. Atalhos globais **⌥⌘Y / ⌥⌘N / ⌥⌘T**, que só existem enquanto há uma pergunta na tela. Se você não responder, ou o iSland estiver fechado, o Claude Code pergunta no terminal como sempre. `AskUserQuestion` e `ExitPlanMode` nunca são oferecidos ao notch.

**M3 — visual.** Forma do notch com as "orelhas" nos cantos de cima; corpo em **Liquid Glass** do macOS 26/27 (3 estilos: *Preto sólido*, *Vidro*, *Vidro claro*), com a pílula fechada sempre preta para se fundir ao hardware; cabeçalho nas laterais do notch ("1 aguardando" / "3 sessões"); respeita *Reduzir transparência* e *Reduzir movimento*.

**O ícone que você pediu:** quando uma sessão está trabalhando aparece o **✻ do Claude Code** (o spinner `· ✢ ✳ ∗ ✻ ✽` que cresce e encolhe, em laranja), no lugar da bolinha, na pílula fechada, no cabeçalho e em cada linha. São caracteres Unicode do sistema, não o arquivo do logo.

**Extras que não estavam no pedido:**
- Clicar numa sessão traz para a frente o app que a hospeda (Terminal, VS Code, app do Claude).
- Sessões somem em até 15 s quando o processo do Claude morre (antes só em 6 h).
- `Notification` de "ocioso esperando seu próximo prompt" agora não acende o alarme vermelho.
- Se você **interrompe** uma resposta (Esc), o Claude Code não manda `Stop`; o ✻ não fica girando para sempre: depois de 5 min sem nenhum evento a sessão passa a "Sem atividade" (um build longo não conta como travado até lá, e qualquer evento novo a reativa).
- O painel transparente só aceita cliques **sobre a ilha**; no resto da área ele é invisível aos cliques (antes, um pedido pendente bloqueava por até 20 s o que estivesse embaixo, como a barra do navegador).
- Interface em **português** e inglês, conforme o idioma do sistema.
- Menu **✻** na barra de menus: estilo, abrir no login, instalar/remover hooks **com tela de consentimento**, sair.
- Primeira abertura oferece instalar os hooks (uma vez).
- Ícone do app (desenhado em código), DMG 0.2.0 com um *leia primeiro* bilíngue.
- 73 testes automatizados, um teste de estresse e um comando único de verificação: `scripts/check.sh --package`.

## 2. Roteiro de verificação (uns 10 minutos)

| # | Faça | Deve acontecer |
|---|---|---|
| 1 | Olhe o notch | Pílula preta discreta; com sessões ativas, um ✻ laranja girando (ou ponto verde/vermelho) ao lado do notch |
| 2 | Passe o mouse no notch | Abre com animação; o cabeçalho mostra o resumo; tire o mouse e fecha |
| 3 | `~/iSland/scripts/demo.sh` | Duas sessões falsas passam por trabalhando, precisa de você e pronto (~20 s) |
| 4 | `~/iSland/scripts/demo-permission.sh` e clique em **Permitir** | O terminal imprime o JSON `{"behavior":"allow"}` que o Claude Code receberia |
| 5 | Repita e aperte **⌥⌘Y** (ou ⌥⌘N) | Mesma resposta, sem mouse. **Não verifiquei isto: preciso que alguém aperte a tecla** |
| 6 | Menu **✻ → Estilo** | Troque entre os três e veja qual você prefere |
| 7 | Abra uma **sessão nova** do Claude Code em modo padrão e peça: *"execute `touch /tmp/island-teste`"* | O cartão aparece no notch com o comando. Esta é a verificação que mais importa: ainda não vi um `PermissionRequest` real |
| 8 | Clique no nome de uma sessão na lista | O app dela vem para a frente. **Também não verifiquei o clique** |
| 9 | Com o cartão aberto (`demo-permission.sh`), clique em algo que está **fora da ilha, mas sob a área transparente** (uma aba do navegador, por exemplo) | O clique deve passar para o que está embaixo. **Lógica revisada, mas não testada com um clique real** |

Se o item 7 não mostrar o cartão, rode `ISLAND_DUMP=/tmp/dump.jsonl claude` num terminal, repita o pedido e me mande o `/tmp/dump.jsonl`: é o payload real do Claude Code e basta para eu ajustar.

## 3. O que está provado e o que não está

**Provado (com evidência):**
- 73 testes passam: JSON, redação de payloads, instalador de hooks (incluindo *instalar e remover devolve o arquivo idêntico, byte a byte*), protocolo sobre sockets reais, adaptador do Claude Code, regras do `SessionStore`.
- 8 cenários de ponta a ponta com os binários reais, **também nos empacotados e assinados**: as 4 decisões, app fechado, ninguém responde, hook que some, `AskUserQuestion`.
- Um clique humano seu respondeu a um pedido de teste (ontem à noite).
- **Formatos reais do Claude Code**, vistos pela captura de esquema (só estrutura): `PostToolUse` traz mesmo o `tool_use_id`, que é o campo que o iSland usa para tirar um cartão da tela quando a ferramenta termina; todos os eventos trazem `permission_mode`. Descoberta de bônus: **esta sessão roda em `bypassPermissions`**, que pula todas as confirmações, e é por isso que ela nunca gerou um pedido real. O teste real precisa de uma sessão em modo padrão.
- O visual: capturado de verdade, com o vidro refratando fundos claro, escuro e cheio — imagens em `docs/screens/` (`glass-*.png`, `clear-*.png`, `solid-*.png`, `*-approval.png`, `closed-pill.png`).
- **Estresse** (`scripts/soak.sh`): 1500 de 1500 eventos entregues com 16 hooks em paralelo, lixo binário e 2 MB sem quebra de linha no socket, 200 conexões penduradas e 60 pedidos de permissão simultâneos sem resposta (todos desistiram sozinhos em 3 s, sem imprimir nada); memória +1 MB; o app não caiu.
- `scripts/check.sh --package` passa (build, testes, e2e, estresse, DMG, assinatura).

**Não verificado por mim:**
- Aparência no **seu desktop real** (as capturas usam um papel de parede sintético).
- Responder no prompt do próprio Claude **enquanto** o cartão está aberto (o que o hook faz: ser cancelado pelo Claude, ou esperar o fim dos 20 s). Nos dois casos o cartão some sozinho; só não observei qual dos dois acontece.
- Os atalhos ⌥⌘Y/N/T: o sistema aceitou registrar os 3, mas não apertei teclas.
- O clique para focar a sessão (a busca do app hospedeiro foi testada com esta sessão: achou o app Claude).
- Instalação do DMG numa conta limpa e o aviso do Gatekeeper.

## 4. Fila de aprovações (nada abaixo foi feito)

Marque o que quiser; cada item diz o que muda.

- [x] **A. Gravação de tela para o app Claude** — *aparentemente concedida (ver a atualização das 07:50).* Ganho: verifico o seu desktop real. Risco: o Claude pode gravar a tela inteira; revogável em Ajustes → Privacidade e Segurança.
- [ ] **B. Instalar o Xcode.** O disco agora tem **63 GB livres** (eram 17 GB), então cabe. Ganho: Preview do SwiftUI, `@State`, Instruments. Não é necessário para o iSland. Precisa do seu Apple ID.
- [ ] **C. Conta Apple Developer (US$ 99/ano)** para assinar com Developer ID e notarizar. Ganho: some o aviso do Gatekeeper e as permissões deixam de zerar a cada atualização. O script já aceita: `SIGN_IDENTITY="Developer ID Application: …" scripts/package.sh`.
- [ ] **D. Atualização automática com Sparkle.** Precisa baixar o pacote (rede), gerar a chave EdDSA no seu Keychain e hospedar um `appcast.xml` público. Depende de C ou de aceitar o atrito atual.
- [ ] **E. Primeiro commit do projeto.** Há ~60 arquivos sem commit (o repositório foi iniciado, nada commitado). Comando: `cd ~/iSland && git add -A && git commit -m "iSland 0.4.0"`. Posso fazer se você disser.
- [ ] **F. Instalar o app de verdade em /Applications** a partir do DMG (`open ~/iSland/dist/iSland-0.4.0.dmg`) e aprovar o Gatekeeper. Antes, encerre a instância de desenvolvimento: `pkill -f "Products/Debug/iSland"`.
- [ ] **G. "Abrir no login"** (menu ✻, só aparece no app instalado). O macOS pode pedir aprovação em Ajustes → Geral → Itens de Login.
- [ ] **H. DMG mais bonito** (janela com fundo e posições): `brew install create-dmg`. Baixa um programa.
- [ ] **I. Publicar** (repositório público, site, releases). Decisão de nome, licença e onde hospedar.
- [ ] **J. Reabrir o boringNotch**, ou aposentá-lo.
- [ ] **K. Certificado local autoassinado para desenvolvimento** ("iSland Dev", no Keychain de login). Ganho: o macOS reconhece cada rebuild como o mesmo app e **não pede a Agenda de novo** a cada compilação. Risco: pequeno (um certificado só seu, sem valor fora deste Mac); exige a sua aprovação para criar e confiar nele. Sem isso funciona igual, só com o pedido repetido. (Desde as 15:15 há um experimento mais simples em andamento, ver a atualização no topo; se funcionar, o K deixa de ser necessário para o desenvolvimento.)

## 5. Decisões que tomei por você (diga se discorda)

| Decisão | Por quê | Como mudar |
|---|---|---|
| Estilo padrão = **Vidro** | É o que você pediu (materiais do macOS 27) | ✻ → Estilo |
| Espera do hook = **20 s** | Mais que isso atrasa demais o prompt do terminal | `ClaudeHook.waitSeconds` |
| Atalhos ⌥⌘Y / N / T | Quase sem conflito, e só existem com um cartão aberto | `ApprovalHotkeys.swift` |
| O notch **não** mostra o texto dos seus prompts | Aparece em compartilhamento de tela | — |
| Botões **opacos**, só o corpo é vidro | O macOS desbota botões de vidro em janelas inativas e o painel nunca é ativo (de propósito, para não roubar o teclado) | — |
| Spinner = glifos do sistema, não o logo | Não dependo de arquivo da marca | `ClaudeSpinner` |
| Só `PermissionRequest` é bloqueante; os outros 7 eventos são `async` | Nunca deixar o agente mais lento | `HookInstaller.ourEntry` |
| O ✻ da barra de menus fica **desligado por padrão** | Pedido seu: os ajustes ficam na engrenagem da ilha | ✻ → *Mostrar ícone na barra de menus* |
| Título do chat = o do app Claude; sem título, a pasta | É o nome que você vê na barra lateral | `SessionIdentityResolver` |
| Cartões de música e agenda **ligados por padrão**, e somem quando há pergunta de permissão | Foi o que você pediu; a pergunta tem prioridade | ✻ → Mostrar música / Mostrar agenda |
| A agenda só mostra o **próximo** evento (sem os de dia inteiro nem os recusados) | Um cartão a mais custa 56 pt de altura | `Agenda.upcoming` |

## 6. Limitações conhecidas

- **Espera do hook:** a documentação diz que o `PermissionRequest` roda *antes* do prompt, mas o `Notification` chegou 6,0 s depois do pedido, o que indica que o prompt do Claude aparece em paralelo ao cartão. Se for assim, você pode responder em qualquer um dos dois sem atraso.
- **Várias telas:** a ilha aparece só na tela do notch. **Tela cheia:** ela fica por cima.
- **Assinatura ad-hoc:** aviso do Gatekeeper na primeira abertura e permissões que zeram a cada atualização (a v1 não pede nenhuma, então não é afetada).
- **Sem Xcode:** `@State` não compila e não há Preview do SwiftUI. Contornado.
- **`hdiutil` está obsoleto** no macOS 27 (avisa para usar `diskutil image`). Funciona; migrar quando quebrar.
- **Ferramenta de captura de dev** (`--selfshot`): só vê as janelas do próprio app, mas é o que dispara o diálogo da seção 0. Não vai no produto.

## 7. Como desfazer / desligar

```bash
~/iSland/.build/out/Products/Debug/iSland --uninstall-hooks   # remove só os hooks do iSland (backup antes)
pkill -f "iSland.app/Contents/MacOS/iSland"                    # fecha o app (a versão .app de desenvolvimento)
pkill -f "Products/Debug/iSland"                               # fecha o app (o binário simples, se for ele que estiver rodando)
open -a boringNotch                                            # reabre o boringNotch
```

O `settings.json` original, de antes de qualquer hook, está em `~/.claude/settings.json.island-backup-20260930-203755`; o segundo backup (`…-210817`) é de quando o `PermissionRequest` virou bloqueante. Tudo do iSland mora em `~/.island` e no próprio `~/iSland`.

## 8. Comandos úteis

| Comando | O que faz |
|---|---|
| `scripts/check.sh --package` | Verifica tudo (build, 130 testes, e2e, estresse, DMG assinado, adaptador de música e texto da permissão dentro do pacote, e2e no empacotado) |
| `scripts/soak.sh` | Teste de estresse isolado |
| `scripts/demo.sh` · `scripts/demo-permission.sh` | Simula sessões e um pedido de permissão |
| `scripts/shots.sh <pasta>` | Refaz as imagens do visual (dispara o diálogo da seção 0) |
| `scripts/package.sh` | Gera `dist/iSland.app` e `dist/iSland-0.4.0.dmg` |
| `scripts/run-bundle.sh` | Compila e abre o `.app` de desenvolvimento no lugar do binário simples (necessário para pedir a Agenda) |
| `iSland -style solid\|glass\|clear` | Escolhe o estilo na linha de comando |

PRD atualizado em [PRD.md](PRD.md); visão geral em [README.md](README.md).

## Rodada segurança/QA/animação/monitores
- Segurança: ver `docs/SECURITY.md`; QA: `docs/QA.md`.
- Fechamento sequenciado (conteúdo sai, depois o container); vidro vive só enquanto aberto (`glassDisplays`), CPU ocioso 0%.
- Multi-monitor: `DisplayChoice` (core), uma `Island` por tela, estado por tela no `SessionStore` (`focusDisplay`, `hiddenPillDisplays`, `glassDisplays`).
