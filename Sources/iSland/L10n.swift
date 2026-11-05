import Foundation
import IslandCore

/// UI strings in English and Brazilian Portuguese, chosen from the system's preferred language.
/// A small table instead of .lproj bundles: the app stays a single binary and the strings sit next to the code.
/// The English text is the key, so a missing translation simply shows English.
///
/// Portuguese is kept short on purpose: the header beside the notch has room for about 14 characters.
/// A small label on a session row that explains how the session treats permissions.
struct ModeBadge: Equatable {
    let text: String
    /// The full explanation, shown as a tooltip.
    let help: String
    /// An SF Symbol name.
    let symbol: String
}

enum L10n {
    static let isPortuguese: Bool = Locale.preferredLanguages.first?.lowercased().hasPrefix("pt") ?? false

    static func t(_ english: String) -> String {
        isPortuguese ? (portuguese[english] ?? english) : english
    }

    /// Strings with one number: `n("%d working", 3)` is "3 working" or "3 trabalhando".
    static func n(_ template: String, _ value: Int) -> String {
        t(template).replacingOccurrences(of: "%d", with: String(value))
    }

    static func installMessage(agent: String = "Claude Code", count: Int, path: String) -> String {
        isPortuguese ? """
        O iSland vai adicionar \(count) hooks em \(path) para que o \(agent) diga a ele o que está fazendo e peça a sua aprovação de permissões pelo notch.

        • Antes, um backup do arquivo é salvo ao lado dele.
        • Nada mais no arquivo muda.
        • Se o iSland não estiver aberto, o \(agent) funciona exatamente como antes.
        • Você pode remover os hooks por este menu a qualquer momento.
        """ : """
        iSland will add \(count) hooks to \(path) so \(agent) can tell it what it is doing, and ask you to approve permissions from the notch.

        • A backup of the file is saved next to it first.
        • Nothing else in the file changes.
        • If iSland is not running, \(agent) behaves exactly as before.
        • You can remove the hooks from this menu at any time.
        """
    }

    static func removeMessage(path: String) -> String {
        isPortuguese
            ? "Só os hooks que o iSland adicionou são removidos. O resto de \(path) fica como está, e um backup é salvo antes."
            : "Only the hooks iSland added are removed. Everything else in \(path) stays as it is, and a backup is saved first."
    }

    /// What to tell the user about a session that does not ask before acting; nil for the ordinary "default" mode.
    static func modeBadge(_ mode: String?) -> ModeBadge? {
        switch mode {
        case "bypassPermissions":
            return ModeBadge(
                text: t("no permission prompts"),
                help: t("This chat runs in bypass-permissions mode: Claude runs commands on its own without asking you first, so no Allow/Deny card will ever appear for it here."),
                symbol: "shield.slash")
        case "acceptEdits":
            return ModeBadge(
                text: t("auto-accepts edits"),
                help: t("This chat approves file edits on its own. Commands and other actions still ask you first."),
                symbol: "pencil")
        case "plan":
            return ModeBadge(
                text: t("planning only"),
                help: t("This chat is in plan mode: Claude only studies the project and proposes a plan, without changing anything until you approve."),
                symbol: "list.bullet.clipboard")
        default:
            return nil
        }
    }

    /// "4 focus periods" / "4 focos"
    static func rounds(_ count: Int) -> String { isPortuguese ? "\(count) focos" : "\(count) focuses" }

    /// "ends in 12 min", "in 25 min", "tomorrow"...
    static func timing(_ timing: Agenda.Timing) -> String {
        func span(_ minutes: Int) -> String {
            guard minutes >= 60 else { return "\(minutes) min" }
            return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
        }
        switch timing {
        case .ongoing(let minutes): return (isPortuguese ? "termina em " : "ends in ") + span(minutes)
        case .startsIn(let minutes): return (isPortuguese ? "em " : "in ") + span(minutes)
        case .today: return t("today")
        case .tomorrow: return t("tomorrow")
        case .later(let date): return date.formatted(.dateTime.weekday(.abbreviated).day())
        }
    }

    /// Session details are produced in English by the store ("Done", "Edit done"...); this localizes them for display.
    static func detail(_ english: String) -> String {
        guard isPortuguese else { return english }
        if let translated = portuguese[english] { return translated }
        if english.hasSuffix(" done") { return String(english.dropLast(5)) + " concluído" }
        return english
    }

    private static let portuguese: [String: String] = [
        // Island
        "Allow": "Permitir",
        "Deny": "Negar",
        "Terminal": "Terminal",
        "Always": "Sempre",
        "Always: ": "Sempre: ",
        "⌥⌘Y allow   ⌥⌘N deny": "⌥⌘Y permitir   ⌥⌘N negar",
        "No active agents": "Nenhum agente ativo",
        "(no details)": "(sem detalhes)",
        "+%d more": "+%d mais",
        "+%d waiting": "+%d na fila",
        "%d waiting": "%d aguardando",
        "%d working": "%d trabalhando",
        "All idle": "Tudo parado",
        "1 session": "1 sessão",
        "%d sessions": "%d sessões",
        // What the agent wants to do
        "Run command": "Executar comando",
        "Edit file": "Editar arquivo",
        "Write file": "Escrever arquivo",
        "Edit notebook": "Editar notebook",
        "Read file": "Ler arquivo",
        "Find files": "Buscar arquivos",
        "Search files": "Pesquisar arquivos",
        "Fetch page": "Abrir página",
        "Search the web": "Pesquisar na web",
        // Session details
        "Done": "Pronto",
        "Started": "Iniciada",
        "Thinking…": "Pensando…",
        "Working": "Trabalhando",
        "Needs approval": "Aguarda aprovação",
        "Asking you a question": "Fez uma pergunta",
        "Plan ready to approve": "Plano para aprovar",
        "Needs you": "Precisa de você",
        "Waiting for your input": "Aguardando você",
        "No activity": "Sem atividade",
        "Approved": "Aprovado",
        "Denied": "Negado",
        "Asking in terminal": "Perguntando no terminal",
        "Asking in chat": "Perguntando no chat",
        "In chat": "No chat",
        // Menu
        "Style": "Estilo",
        "Solid black": "Preto sólido",
        "Glass": "Vidro",
        "Clear glass": "Vidro claro",
        "Launch at login": "Abrir no login",
        "Sounds": "Sons",
        "Show music": "Mostrar música",
        "Show calendar": "Mostrar agenda",
        "Calendar: %@": "Agenda: %@",
        "Calendar: no access yet": "Agenda: sem acesso ainda",
        "Add a Google account…": "Adicionar conta Google…",
        "Unknown track": "Faixa desconhecida",
        "Previous": "Anterior",
        "Pause": "Pausar",
        "Play": "Tocar",
        "Next": "Próxima",
        "Join": "Entrar",
        "Connect": "Conectar",
        "Show your calendar here": "Mostrar sua agenda aqui",
        "Calendar access is off": "Agenda sem acesso",
        "Open Settings": "Abrir Ajustes",
        "(untitled)": "(sem título)",
        "today": "hoje",
        "tomorrow": "amanhã",
        "Hide from screen sharing": "Ocultar em compartilhamento de tela",
        "no permission prompts": "sem pedir permissão",
        "auto-accepts edits": "edições automáticas",
        "planning only": "só planejando",
        "This chat runs in bypass-permissions mode: Claude runs commands on its own without asking you first, so no Allow/Deny card will ever appear for it here.":
            "Este chat roda no modo de ignorar permissões: o Claude executa os comandos sozinho, sem pedir a sua aprovação. Por isso nenhum cartão de Permitir/Negar aparece para ele aqui.",
        "This chat approves file edits on its own. Commands and other actions still ask you first.":
            "Este chat aprova sozinho as edições de arquivos. Comandos e outras ações ainda pedem a sua permissão.",
        "This chat is in plan mode: Claude only studies the project and proposes a plan, without changing anything until you approve.":
            "Este chat está em modo de planejamento: o Claude só estuda o projeto e propõe um plano, sem alterar nada até você aprovar.",
        "Settings": "Ajustes",
        "Too long or odd to approve here: check it in the terminal": "Longo ou estranho demais para aprovar aqui: confira no terminal",
        "Hide in full-screen video": "Esconder em vídeo em tela cheia",
        "First steps…": "Primeiros passos…",
        "Welcome to iSland": "Boas-vindas ao iSland",
        "Your notch becomes a control surface for AI agents. You see what each chat is doing, approve permissions without leaving what you are doing, and jump to the right chat with a click.": "O seu notch vira uma superfície de controle para agentes de IA. Você vê o que cada chat está fazendo, aprova permissões sem sair do que está fazendo e vai direto ao chat certo com um clique.",
        "Rest the pointer on the notch to open it. The gear inside is where all the settings live.": "Deixe o mouse parado no notch para abri-lo. A engrenagem lá dentro é onde ficam todos os ajustes.",
        "Connect your agents": "Conecte os seus agentes",
        "iSland learns what an agent is doing through its hooks. Connecting adds them to the agent's own settings file, after saving a backup, and touches nothing else. You can undo it from the settings menu.": "O iSland sabe o que um agente está fazendo pelos hooks dele. Conectar adiciona os hooks ao arquivo de ajustes do próprio agente, depois de salvar um backup, e não mexe em mais nada. Dá para desfazer pelo menu de ajustes.",
        "In Codex, run /hooks once and approve iSland's hooks.": "No Codex, rode /hooks uma vez e aprove os hooks do iSland.",
        "Not found on this Mac": "Não encontrado neste Mac",
        "Connected": "Conectado",
        "Your calendar": "Sua agenda",
        "iSland can show the next event with a Join button, from the calendars your Mac already syncs. For Google Calendar, add your Google account in System Settings → Internet Accounts with Calendars turned on.": "O iSland pode mostrar o próximo evento com um botão Entrar, a partir das agendas que o seu Mac já sincroniza. Para o Google Agenda, adicione a conta Google em Ajustes do Sistema → Contas de Internet, com Calendários ligado.",
        "Show my calendar": "Mostrar minha agenda",
        "Available in the installed app.": "Disponível no app instalado.",
        "Nothing is read until you press the button, and nothing leaves your Mac.": "Nada é lido antes de você apertar o botão, e nada sai do seu Mac.",
        "Mirror and photos": "Espelho e fotos",
        "The mirror icon in the notch turns your camera on while you look at yourself, and its round button takes a photo for when you need a picture in a hurry. macOS asks for the camera the first time you use it; photos go to Pictures/iSland only after you allow that.": "O ícone de espelho no notch liga a câmera para você se ver, e o botão redondo tira uma foto para quando precisar de uma imagem com urgência. O macOS pede a câmera na primeira vez; as fotos vão para Imagens/iSland só depois de você permitir.",
        "The camera is on only while the mirror is showing, and nothing is recorded or sent anywhere.": "A câmera só fica ligada enquanto o espelho aparece, e nada é gravado nem enviado para lugar nenhum.",
        "All set": "Tudo pronto",
        "Pomodoro with focus and breaks": "Pomodoro com foco e pausas",
        "Start a new chat in a recent folder": "Comece um chat novo numa pasta recente",
        "Take a chat off the list with the ×": "Tire um chat da lista com o ×",
        "Everything else is in the gear, including this guide": "O resto está na engrenagem, inclusive este guia",
        "Next step": "Próximo",
        "Finish": "Concluir",
        "Animation": "Animação",
        "Displays": "Telas",
        "Here": "Aqui",
        "You are here": "Você está aqui",
        "Main display": "Tela principal",
        "All displays": "Todas as telas",
        "Smooth (Apple)": "Suave (padrão Apple)",
        "Bouncy (boring.notch)": "Elástica (boring.notch)",
        "All day": "O dia todo",
        "Take photo": "Tirar foto",
        "Photo saved": "Foto salva",
        "Show": "Mostrar",
        "Save photos in Pictures?": "Salvar fotos em Imagens?",
        "They stay in Pictures/iSland and never leave your Mac.": "Ficam em Imagens/iSland e nunca saem do seu Mac.",
        "Not now": "Agora não",
        "Time to open": "Tempo para abrir",
        "Instant": "Instantâneo",
        "default": "padrão",
        "See how I look": "Ver como estou",
        "New chat": "Novo chat",
        "No recent folders": "Nenhuma pasta recente",
        "Stop": "Parar",
        "Focus done": "Foco concluído",
        "Pomodoro…": "Pomodoro…",
        "Long break every": "Pausa longa a cada",
        "Start": "Iniciar",
        "Stop pomodoro": "Parar pomodoro",
        "Pomodoro": "Pomodoro",
        "Focus": "Foco",
        "Short break": "Pausa curta",
        "Long break": "Pausa longa",
        "Break is over": "A pausa acabou",
        "Start focus": "Iniciar foco",
        "Resume": "Continuar",
        "Skip": "Pular",
        "Mirror": "Espelho",
        "Back": "Voltar",
        "Remove from the list": "Remover da lista",
        "Turning the camera on…": "Ligando a câmera…",
        "Camera access is off": "Câmera sem acesso",
        "No camera available": "Nenhuma câmera disponível",
        "Show icon in menu bar": "Mostrar ícone na barra de menus",
        "Quit iSland": "Sair do iSland",
        "%@ hooks: installed": "Hooks do %@: instalados",
        "%@ hooks: not installed": "Hooks do %@: não instalados",
        "%@ hooks: %d of %d installed": "Hooks do %@: %d de %d instalados",
        "%@: not found": "%@: não encontrado",
        "Install %@ hooks…": "Instalar hooks do %@…",
        "Remove %@ hooks…": "Remover hooks do %@…",
        "Install": "Instalar",
        "Remove": "Remover",
        "Cancel": "Cancelar",
        "Install the %@ hooks?": "Instalar os hooks do %@?",
        "Remove the %@ hooks?": "Remover os hooks do %@?",
        "Hooks installed": "Hooks instalados",
        "Hooks removed": "Hooks removidos",
        "Could not install the hooks": "Não foi possível instalar os hooks",
        "Could not remove the hooks": "Não foi possível remover os hooks",
        "Start a new %@ session to see it in the notch.": "Abra uma nova sessão do %@ para vê-lo no notch.",
        "Codex asks you to trust new hooks: run /hooks in Codex once and approve iSland's.": "O Codex pede para você confiar em hooks novos: rode /hooks no Codex uma vez e aprove os do iSland.",
        "Backup: ": "Backup: ",
        "Could not change the login item": "Não foi possível alterar a abertura no login",
        "Allow it in System Settings > General > Login Items.": "Autorize em Ajustes do Sistema > Geral > Itens de Login.",
    ]
}
