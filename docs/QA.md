# iSland — QA

## Automático (`scripts/check.sh --package`)
- Chaves duplicadas na tabela PT, checksum do adapter, build, 190 testes (core + app), e2e hook↔ilha (debug e pacote), stress (1500 eventos, lixo, 60 perguntas simultâneas), `.app`+DMG, assinatura válida, textos de permissão dentro do pacote.
- Soak (`scripts/soak.sh`): estável 3/3. CPU ociosa 0,0 %. Zero conexões de rede.

## Corrigido nesta rodada
Endurecimento do socket; sanitização e `needsReview`; consentimento da câmera/Fotos inline (o alerta não era clicável); animação de fechamento em sequência (tira os elementos, depois fecha; sem artefatos); regressão de CPU do vidro; vários monitores.

## Plano manual (do seu lado)
1. Codex e Gemini reais: instalar hooks, rodar um turno, ver spinner/status.
2. Vídeo em tela cheia (YouTube/Netflix): ícones somem e voltam; tela cheia sem vídeo mantém.
3. Segundo monitor: padrão = só tela principal; testar "Todas as telas" e uma tela específica; desplugar o monitor com a ilha aberta.
4. Mac sem notch (ou `--no-notch`), idioma EN, modo escuro/claro, reduzir movimento/transparência.
5. DMG em conta limpa do macOS (Gatekeeper, permissões, primeira abertura guiada).

## Lacunas conhecidas
Spinners animados custam ~4–6 % de CPU enquanto visíveis; um frame de engasgo no primeiro hover não explicado; vários monitores testado só com um monitor físico (lógica coberta por testes unitários).
