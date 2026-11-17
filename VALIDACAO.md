> Publication update (2026-10-23): the maintainer authorized the public repository and both GitHub packages. Earlier private-development entries below are historical. The primary README and release notes contain the current English summary.

# Validação privada — 2026-10-23

Repositório privado, release v0.1.0 em rascunho. Nenhuma publicação pública autorizada. Extensão instalada: 0.1.1. Terminal próprio: primeira versão nativa 0.2.0, ainda experimental e sem notarização.

## Matriz verificada

| Ambiente | Entrada | Resultado |
| --- | --- | --- |
| Extensão VS Code | 10 testes unitários | Passaram; controlos, Unicode, terminal de origem, cancelamento, falhas e encerramento |
| Extensão VS Code / terminal normal | Microfone físico curto + voz do responsável | Teste acústico passou; responsável confirmou manualmente o ditado |
| Terminal nativo / PTY | Texto sem Enter; depois Enter explícito de controlo | O programa só recebeu uma submissão depois do Enter de controlo; resize passou |
| Terminal nativo / gravação longa controlada | Reprodução pelos altifalantes + microfone físico | 82,10 s de áudio; 82,11 s indicados pelo gravador; 182 palavras reconhecidas; início e fim preservados; prefixo anterior preservado; sem Enter |
| Terminal nativo / Codex CLI 0.163.0 | Transcrição longa em sessão nova | Rascunho visível, prefixo preservado, sessão ativa, sem Enter |
| Terminal nativo / Claude Code 2.1.309 | Transcrição longa em sessão nova | Bloco `Pasted text` mantido no compositor, prefixo preservado, sem Enter |
| VS Code / Codex CLI 0.163.0 | Ficheiro sintético longo, ASR real, processo CLI e PTY reais | 182 palavras, 1121 caracteres; bloco de conteúdo colado visível; sem Return |
| VS Code / Claude Code 2.1.309 | Mesmo percurso ASR → extensão → PTY → CLI | 182 palavras, 1121 caracteres; rascunho/bloco visível; sem Return |
| Gemini CLI | Abertura e autenticação | Bloqueado pelo serviço: cliente não suportado para a conta Google atual. Sem validação do compositor |

Os testes dos CLIs deixaram os textos **por enviar**. Não se pediu uma resposta aos modelos, nem se autorizou execução de tarefas por esses agentes. O percurso do VS Code usou o conteúdo da extensão instalada 0.1.1 e um pseudo-terminal de teste com processo CLI real; não é uma sessão do responsável reutilizada.

## Fala longa: calibração e limites

O parágrafo de teste tem 182 palavras e está em `test/fixtures/long-dictation.txt`. Dois primeiros ensaios acústicos produziram cerca de 160 palavras, com perda de partes do início ou do fim. Não foram tratados como aprovação da cobertura da fala.

A leitura direta do ficheiro sintético preservou início e fim, ajudando a separar reconhecimento/inserção da captação acústica. No ensaio controlado final, com estabilização antes da reprodução e sem novas janelas de CLI a arrancar durante a medição, a duração do ficheiro coincidiu com a do gravador e as 182 palavras chegaram ao prompt. A contagem não garante correspondência palavra por palavra: termos e pontuação podem ser substituídos.

Isto **não é** um benchmark de precisão nem uma validação da fala longa natural do responsável. Esse teste continua pendente. Nos ensaios de inserção, compara-se o texto efetivamente reconhecido com os bytes entregues ao PTY, não com uma transcrição inventada.

O motor devolve apenas as durações como metadados adicionais, sem guardar áudio ou histórico de texto. Os ficheiros locais de diagnóstico não são publicados no repositório. A imagem do README mostra apenas material sintético de teste.

## Gemini

O Gemini abriu inicialmente na versão 0.45.0, iniciou o seu próprio atualizador e passou para 0.65.0. O erro do serviço persistiu depois da atualização: `This client is no longer supported for Gemini Code Assist for individuals`. A janela de autenticação ficou disponível para o responsável; não se extraíram credenciais nem se contornou a autenticação. O teste é pendente, não aprovado.

## Segurança dos testes

- Sessões novas, diretórios temporários e prompts sintéticos.
- Codex em sandbox de leitura e sem daemon partilhado.
- Claude em safe mode, sem ferramentas nem MCP adicionais. Confirmação de pasta limitada a um diretório de teste vazio.
- Gemini mantido sem confiança na pasta e sem extensões adicionais.
- Ausência de Return confirmada na entrega ao PTY. Claude/Codex podem representar colagens longas como blocos recolhidos; isso não significa envio.
- Assinaturas ad hoc verificadas, incluindo o helper incorporado no terminal.

## Correções e implementação

A extensão 0.1.1 já corrigia a escrita de `cancel` num pipe que podia estar fechado, gerando SIGPIPE depois da transcrição. Usa o encerramento gracioso do helper por SIGTERM e mantém a escalada para SIGKILL se necessário.

O novo terminal utiliza o mesmo helper, uma shell em PTY, AppKit e xterm.js em WebKit. A saída do PTY é passada como bytes, a entrada de voz usa o caminho de paste do xterm e a escrita respeita bracketed paste quando o programa o solicita. O frontend só carrega recursos locais e bloqueia navegação externa. Erros de entrega preservam o ditado numa janela de recuperação.

Durante a construção, os testes detetaram uma leitura de pipe que esperava mais bytes antes de atualizar o frontend; foi substituída por leitura POSIX da quantidade disponível. Os testes nativos cobrem a shell e a ausência de submissão sem Enter.

Os primeiros testes de CLI no VS Code tinham pressupostos errados sobre blocos de colagem e prontidão do ecrã de confiança. O harness foi corrigido e os dois testes finais passaram. Não houve alteração do comportamento de envio da extensão para os fazer passar.

## Por validar

- Fala longa natural do responsável e mais condições acústicas.
- Compositor do Gemini depois de resolver o método de autenticação.
- Instalação limpa com permissões recusadas e interrupções de áudio.
- Sessões remotas e uso prolongado/recursos sob carga.
- Terminal nativo: estabilidade continuada, acessibilidade completa e distribuição notarizada. Ainda só tem uma janela/sessão, sem tabs nem restauro.
- Recaptura visual do build final: o Mac bloqueou antes da captura após os ajustes menores de foco/cor do microfone. A revisão independente devolveu `recapture`; não houve aprovação visual final. A captura atual do README é do ensaio anterior do protótipo.

Os testes automatizados fecham apenas as suas próprias janelas quando terminam. Uma janela normal do VozTTY ou do VS Code permanece aberta.

## Continuação — cliente Google suportado (23/10/2026)

A pesquisa nas fontes oficiais confirmou a migração de contas pessoais para Antigravity CLI: https://github.com/google-gemini/gemini-cli/discussions/27274 e https://antigravity.google/docs/getting-started/. Instalado `agy` 1.4.6 pela distribuição oficial via Homebrew Cask. Aberto dentro de uma cópia do VozTTY, em modo `plan`, fora do repositório privado. O fluxo avançou do login para a configuração e mostrou Gemini 4 Argon. Parou nos termos de serviço, que precisam de decisão do responsável; a partilha de interações surge marcada por defeito. Não se aceitou o acordo nem se alterou essa opção. A inserção de rascunho longo no Antigravity ainda não foi validada.

## Antigravity e tema preto — 23/10/2026

Após o responsável concluir login e termos, Antigravity CLI 1.4.6 abriu Gemini 4 Argon. Teste no compositor real do terminal nativo, tema preto: 182 palavras/1130 caracteres de uma transcrição sintética previamente reconhecida; prefixo preservado, bloco de colagem visível, bytes recebidos iguais ao texto, processo ativo e nenhum Enter enviado. Evidência local: work/antigravity-black-final.json. Isto valida inserção no terminal próprio; microfone direto com Antigravity e extensão VS Code com Antigravity ainda não foram repetidos.

## Confirmação manual do responsável — Antigravity

Em 23/10/2026, o responsável repetiu o teste com o microfone e confirmou sucesso no Antigravity, mostrando o rascunho “Testando o microfone testando o microfone.” no compositor. Confirma ditado curto com a voz natural; não equivale a um novo teste longo.

Na continuação, a aplicação instalada abriu Codex 0.163.0 e a UI mostrou o ditado natural do responsável “Testando o microfone no OpenI Codex.” como rascunho. Nenhum prompt foi submetido pelo agente. A sessão herdou a configuração local YOLO e abriu em /; definir uma pasta de projeto e permissões antes de executar trabalho. A transcrição de nomes próprios pode precisar de revisão.

## Confirmação manual do responsável — Claude Code

Em 23/10/2026, o responsável mostrou Claude Code 2.1.309, Opus 5.5, aberto na pasta VozTTY. A frase ditada “Testando o microfone no Cloud, testando o microfone do Cloud.” foi recebida e respondida pelo Claude. Confirma o percurso de voz natural até ao CLI, com substituição do nome Claude por Cloud; rever nomes próprios antes de enviar. O envio foi feito pelo responsável, não pelo teste automatizado. Com esta confirmação, os três clientes — Codex, Claude Code e Antigravity — têm teste manual curto de microfone confirmado. Não equivale a teste longo com a voz natural. Os avisos de regras e expiração do login pertencem à configuração do Claude e não foram alterados.

## Organização visual e destaque de perguntas — 23/10/2026

- Perguntas reconhecidas pelos marcadores ›, ❯ e > em azul suave, incluindo quebras automáticas; saída normal mantém o tom claro e as cores ANSI originais. Não são alterados bytes do PTY, texto ou envio.
- Cabeçalho com identidade/estado agrupados; rodapé com legenda e atalhos; margens de leitura ampliadas.
- 12 testes unitários: 10 da extensão e 2 de reconhecimento visual, Unicode, quebras e linhas reutilizadas.
- Codex real: 182 palavras/1130 caracteres, prefixo e bloco mantidos, transporte exato, nenhum Enter, uma linha com destaque e seleção preservada. Evidência local: work/conversation-codex.json.
- Prévia nativa capturada com conversa sintética identificada: assets/terminal-conversation.png. Não apresenta conteúdo gerado por um modelo.
- A primeira verificação do destaque correu antes do primeiro desenho de uma janela em segundo plano; foi corrigida a espera visual no teste. Um aviso de atualização do Codex interrompeu a segunda execução; o teste passou a dispensá-lo com Escape, sem instalar atualizações ou alterar definições globais.
- Limite: são marcadores visuais, não metadados de autor. Citações com o mesmo prefixo podem ficar azuis; continuações com quebra explícita sem marcador podem conservar a cor do CLI. O tema da extensão VS Code não foi alterado.

## Correção do ícone macOS — 23/10/2026

Confirmado no ICNS instalado: o fundo verde estava presente e o símbolo ausente. A conversão do SVG não preservou o caminho com stroke. Substituído o símbolo por geometria preenchida equivalente e reexportados os dez tamanhos standard/Retina. O novo build-icon.sh verifica os dois componentes do símbolo antes da conversão e o símbolo depois de descodificar o ICNS. Sem alterar permissões ou encerrar sessões para limpar caches do Dock.

## Corte na lateral / ajuste de colunas — 23/10/2026

Reproduzido no binário anterior: o pai medido pelo FitAddon tinha padding, mas a medição usava a largura total como espaço para a grelha. A grelha ficou fora do limite direito (8 px medidos), com 131 colunas a 1120 px. Margens movidas para body; o pai do xterm ficou sem padding, mantendo o mesmo espaçamento visual.

Teste nativo de regressão em WKWebView: 1120 → 620 → 800 → 1440 → 1120 px. Com a correção, colunas 125 → 66 → 87 → 163 → 125, sem extravasamento à direita ou em baixo. O teste espera a conclusão do FitAddon em cada tamanho, em vez de aceitar uma grelha antiga menor. Antes falhou; depois passou. Evidência local: work/bounds-before.json e work/bounds-final.json. Não depende de login, voz ou prompts enviados.

## Controlos da janela — 23/10/2026

Barra de título nativa visível e três botões permanentes no cabeçalho: minimizar, maximizar/restaurar e fechar. Usam ações nativas NSWindow, com labels acessíveis e tooltips. Verificados no CUA numa instância de prévia com conteúdo sintético: os três botões estão presentes; maximizar/restaurar funcionou; fechar mostrou a confirmação e Keep Open preservou a sessão. O botão minimizar foi acionado; a inspeção CUA voltou a apresentar a janela, pelo que não se confirmou persistência no Dock. Sem encerrar sessões do responsável.

## Public release preparation — 2026-10-23

The maintainer explicitly authorized public GitHub distribution of both products. Extension 0.1.2 adds English command names, status/error text and permission descriptions without changing the dictation lifecycle or command IDs. The shared helper's own messages are now English. Terminal 0.2.0 includes the existing window/layout/icon fixes and a bundled MIT license.

Release checks passed: 12 JavaScript unit tests; native text/PTY/resize checks; packaged VSIX 0.1.2 exercised in an isolated VS Code Extension Development Host with real Apple recognition on the synthetic 182-word audio, exact terminal delivery and no automatic Enter; archive contents and checksum checks; deep/strict code-signature verification after extracting the native ZIP. Test hooks and internal design/checkpoint files are excluded from installable packages. Finder metadata was removed by staging the final archive outside the synced Documents directory before verifying the extracted signature.

The full Git history was scanned for secrets. Two generic-key matches were inside the unmodified xterm.js bundle; its bytes were verified against the official @xterm/xterm 6.0.0 npm archive (SHA-256 14903579ff54664cd72f8e8699e6961a6272c21863ec1c3b118cdc8af5d4a972). Only those exact historical fingerprints were excluded from the local audit; no other findings remained. Diagnostics, recordings and scanner reports stay outside the repository. Packages remain ad hoc signed and not Apple-notarized.

Publication verified: GitHub repository PUBLIC; v0.2.0 published as a public prerelease with both binary packages and SHA256SUMS.txt. All three assets downloaded without authentication and matched the local files byte for byte. English README accessible without login. No VS Code Marketplace publication was performed.

## Native 0.2.1 usability update — 2026-10-23

Removed the duplicate window buttons from the content header at the maintainer's request. Standard macOS close/minimize/zoom controls remain. The voice header now uses readable language names, a clearer Dictate action, shorter keyboard hints and clearer listening/review guidance. Existing language IDs and preferences are preserved through menu-item represented values.

The native layout regression passed at 1120 → 620 → 800 → 1440 → 1120 px with no grid overflow. All three displayed language choices map to the supported pt-BR, pt-PT and en-US identifiers; the test restores its original selection without changing saved preferences. Local evidence: work/native-021-layout.json. No new microphone run was performed for this UI-only patch.

Native 0.2.1 installed with a verified code signature. Public prerelease v0.2.1 includes the new native ZIP, unchanged VSIX 0.1.2 and checksums. All assets downloaded without authentication and matched local files byte for byte. Previous release assets were not overwritten.

## Native voice panel — source build 0.2.2

Controlled acoustic checks through the physical microphone passed in English and Brazilian Portuguese: real level events moved the seven bars; Pause stopped metering; speech played during Pause was excluded; the first and final sentences on either side of Pause were retained; Stop & insert also worked while paused; PTY bytes matched the transcript without Return. These checks use synthetic speaker playback, not a natural-voice accuracy benchmark. Window-fit checks with the panel visible passed at 620, 800, 1120 and 1440 pixels, and all recording states produced the expected enabled/disabled controls. Twelve JavaScript unit checks and native PTY/sanitization checks also passed. The public 0.2.1 assets and VS Code extension are unchanged.

## Continuous voice history — native source build 0.2.3

Fifteen JavaScript checks pass, including time-positioned level history, completed/ongoing pause intervals, expiry after 20 seconds, and rejection of invalid geometry. Native layout checks with synthetic level history and pause bands pass at 620, 800, 1120 and 1440 px without grid overflow. The narrow layout retains more terminal space. The visual preview is explicitly synthetic. A fresh physical-microphone recheck waited for macOS authorization and timed out before recording; diagnostic instrumentation in an untracked test copy confirmed the wait at AVCaptureDevice.requestAccess. This run does not claim a new acoustic pass. The helper protocol and recognition engine are unchanged from 0.2.2.

### Microphone authorization follow-up — 0.2.3

After the maintainer authorized microphone access in macOS, the physical-microphone recheck passed with 99 real meter events. The continuous history reacted to audio; paused speech was excluded; the first and final sentences on either side of the pause were retained; Stop & insert worked while paused; the PTY received exactly the recognized text without Return. This used controlled synthetic Portuguese speech through the speakers and the physical microphone, not a natural-voice accuracy benchmark. The previous authorization blocker is resolved. Local evidence: work/continuous-microphone-authorized.json (not published).

## Compact voice line — native source build 0.2.4

Visual-only refinement: a transparent, borderless 40 px grid row with a 28 px waveform, muted monospace labels, and text controls. Native layout/history checks passed at 620, 800, 1120 and 1440 px with zero grid overflow. At 1120 px the terminal gains six visible rows compared with 0.2.3; at 620 px it gains five. Synthetic history was used for visual review. Microphone recognition was not rerun for this CSS-only change. Installed locally; public release assets remain 0.2.1. Owned preview windows were closed, preserving working app sessions.


## Boterm 0.3.0 — 2026-11-13

- 23 Node tests passed, including Ctrl+C selection/SIGINT and paste shortcuts.
- Native unit checks passed: real PTY, Unicode sanitization, resize, no Enter without submission, installed-theme lookup with JSONC, inherited theme colors, overrides and invalid-color rejection.
- Native workspace harness passed: independent processes retained across tabs; cross-project messages and reads rejected; native clipboard copy and paste without Return; explicit input submission ordered after paste; dictation completion delivered to its original session after switching focus.
- Native agent-launch harness passed: the UI selector starts the real installed Codex CLI with its name/symbol and running-state badge, without submitting a model prompt.
- Native layout harness passed 620, 800, 1120 and 1440 px with no terminal overflow; all voice panel states and the rolling waveform/pause-history renderer passed. Voice visual fixtures are synthetic; no fresh real-microphone accuracy benchmark.
- `test/control.integration.py` passed against the running app: real MCP stdio -> Unix socket -> app messages/inbox, error handling and ancestry-based identity after BOTERM environment variables are removed. Generated per-session Codex configuration is checked with the actual installed CLI.
- Two actual Codex agents in separate terminals exchanged a request and acknowledgment using the Boterm MCP tools with read-only shell sandboxing. No code files were read/edited by those test agents. Claude was not logged in; a real Claude/Gemini/OpenCode conversation was not verified.
- Public app name/icon are Boterm. Release build is signed with the existing Danyalgil Developer ID and retains the bundle identifier. No GitHub release or remote repository rename in this task.

Messages are bounded in-memory history, not a durable task queue. CLI process state is not model token-generation state. Agent inbox checks are explicit; a message does not automatically start a model turn. Closing Boterm ends its PTYs; no restart/reboot persistence.

## Boterm layout refinement — 2026-11-13

Projects now start immediately below the native title bar. Removed the duplicated brand/header; native dictation status, language and microphone controls sit in the footer, and the waveform follows terminal output. Reduced sidebar width, removed the single-pane frame and allowed toolbar actions to wrap.

The native layout harness passed at 620×380, 800×600, 1120×720 and 1440×900, with no grid or page overflow; voice lifecycle/language IDs and pause history passed. WKWebView captures at 620 and 1120 were inspected. Workspace integration passed peer output reading, workspace isolation, clipboard/draft insertion, explicit submission ordering and dictation origin preservation. No physical microphone recheck in this pass. Existing sessions are preserved when installing; they keep their loaded native UI until restarted.

## Boterm commit verification — 2026-11-13

A real read-only Codex reviewer was launched in a separate Boterm terminal and exchanged request/report messages through MCP. Its review found that control requests trusted client-provided session IDs. Requests now require the kernel-reported peer process to descend from the claimed session's shell. The real-socket regression rejects a forged identity while preserving valid MCP messages/inbox, filtered-environment ancestry discovery and actual Codex configuration parsing. The control test now creates a fresh terminal so a previous draft cannot contaminate its shell command.

The 23 JavaScript tests, native unit checks and workspace integration passed. Layout passed at 620–1440 px; the native agent selector launched the installed Codex. The source snapshot prepared for the commit is isolated from concurrent interface edits. Diagnostics and agent transcripts remain under ignored work/. No new physical microphone test, Claude/Gemini/OpenCode conversation, installed-app replacement or binary release is included. Message history remains an intentionally bounded shared window history (200 messages across its projects), not a durable queue or an OS security sandbox.

## Boterm — personalização local, build 13 (2026-11-13)

- 25 testes JavaScript passaram, incluindo variáveis, posições Unicode, preservação de ANSI e limpeza de decorações.
- Harness nativo `customize`: cores estáveis, lateral redimensionável, altura/largura dos splits, altura da equipe, eventos de drag/drop, reordenação sem recriar o terminal, renomeação de projeto (Enter/Escape/vazio e atualização de fundo), + antes de Private Project e normal/alternate buffer. Quatro terminais divididos cabem em 620×380, 800×600, 1440×900 e 1120×720.
- Harness nativo `layout`: cinco tamanhos entre 620 e 1440 px, sem overflow da grade, e ciclo visual dos controles de ditado preservado.
- Captura WKWebView revisada localmente em `work/customize-check/preview.png`. Eventos de drag/drop são automatizados; o gesto físico de arrastar com o mouse não foi repetido. Nenhum modelo foi acionado e nenhum microfone foi aberto nesta validação.
- Nomes/layout não são restaurados ao reabrir a janela. As alturas são compartilhadas por linha e larguras por coluna; o realce extra usa o buffer normal e deixa as cores dos aplicativos de tela cheia intactas.

## Build 14 — 2026-11-13

- 27 testes JS aprovados, incluindo funções do preset e realce de comandos, Kotlin/configurações, estados e diffs.
- Harness nativo `terminal-development.js`: hover/Escape do menu, lápis por foco, Sobre/crédito, sete funções, rejeição de pasta inexistente, sete processos de teste com diretório e prompts corretos; Gemini com --prompt-interactive. Metacaracteres no objetivo permanecem literais e não executam comandos. Executáveis de teste substituem provedores somente no bundle temporário.
- Regressão `terminal-customize.js` aprovada: redimensionamento, reordenação, renomeação, isolamento do buffer alternativo e preservação de instâncias. Ambos os harnesses cabem em 620, 800, 1120 e 1440 px.
- Captura estável revisada em work/development-check/preview.png; ícone conferido a 64 px e exportado em dez representações ICNS. Sem conversa nova com modelos reais, teste de login dos provedores ou ciclo completo autônomo. Sem novo teste físico de microfone.
- Unidade nativa e harness workspace aprovados: PTY real, resize, sem Enter no paste/ditado, origem do ditado, clipboard, socket, mensagens, leitura de pares, separação de projetos e estado após saída. Build 14 assinado com Developer ID e instalado em /Applications/Boterm.app; bundle anterior preservado em work/development-check/Boterm-before-build14.app, sem encerrar as sessões existentes.
- Verificação final inclui bloqueio de criação duplicada enquanto a equipe está ativa. O harness aguarda o layout nativo da janela antes de medir o terminal após resize; resultado final passou nas quatro dimensões. Bundle final instalado com essa proteção.

## Build 15 — crédito e ícone no sistema

Sobre validado no harness nativo com o crédito Ricardo Danyalgil Junior, aviso open source/MIT e URL do GitHub. Link abre apenas o repositório autorizado no navegador padrão após clique. Build assinado e instalado em /Applications/Boterm.app. Exportação ICNS regenerada pelo script e comparada ao ícone instalado. Registro do macOS/Dock atualizado; o ícone retornado por NSWorkspace foi inspecionado e contém o novo símbolo >_ menta. Sessões antigas preservadas; sua imagem em execução pode persistir até serem reabertas. Abertura real do navegador pelo link não foi automatizada.

## Boterm — pastas e projetos recentes, build 16 (2026-11-13)

- Seletor nativo de diretórios validado por clique, navegação e confirmação: caminho preenchido, objetivo preservado, sem iniciar a equipe. Cancelamento e configuração de pasta única também verificados no harness nativo.
- Histórico local: limite de dez, ordem por uso, deduplicação e exclusão de pastas indisponíveis aprovados com preferências isoladas. Menu do Dock inspecionado pelo harness; clicar no item abriu uma janela com projeto nomeado e `pwd` real na pasta correta. O clique direito visual no Dock não foi validado: o acesso à UI do Dock expirou.
- Harness de desenvolvimento aprovado: quatro atalhos recentes, seleção sem alterar o objetivo, caminhos com espaços/aspas, pasta inválida rejeitada e sete processos de teste com diretórios e funções corretos. Tamanhos 620×380, 800×600, 1440×900 e 1120×720 sem overflow. Provedores substituídos por stub somente no bundle de teste.
- `npm test`: 27 testes aprovados. Build 16 assinado com Developer ID, verificado e instalado em `/Applications/Boterm.app`; build 15 preservado em `work/development-check/Boterm-before-build16.app`. Sessões do app anterior não foram encerradas.

O histórico registra pastas escolhidas/abertas a partir desta versão; não reconstrói uso anterior nem restaura conversas dos provedores. As janelas abertas continuam na seção padrão de janelas do macOS.

## Boterm — histórico local, 0.3.1 / build 17 (2026-11-13)

- Harness nativo `VOZ_TEST_MODE=history` aprovado: arquivo UTF-8 com acentos e metacaracteres literais, nomes únicos, permissões 0700/0600, captura acima do antigo limite de 262.144 caracteres, mensagens da equipe, cancelamento mantendo janela e sessão, falha de captura mantendo a sessão aberta, gravação antes de autorizar fechamento e descarte encerrando apenas a sessão escolhida.
- Confirmação visual no app de teste com duas janelas: ⌘Q mostrou Salvar e fechar / Fechar sem salvar / Cancelar; Cancelar manteve a janela utilizável. Saída repetida apresentou uma confirmação por janela. O app de teste foi encerrado separadamente; não foram encerradas sessões do app do usuário.
- `npm test`: 27 testes aprovados. Build de produção compilado em Swift 6, assinado com o Developer ID existente e verificado com `codesign --verify --deep --strict`. Instalado em `/Applications/Boterm.app`, versão 0.3.1/build 17; cópia anterior em `work/development-check/Boterm-before-build17.app`.
- Nova instância de produção aberta sem encerrar a instância antiga. O Dock já tinha um item fixado para `/Applications/Boterm.app`; não foi necessário alterar a configuração do Dock.

Os arquivos contêm a saída ainda disponível no buffer e as mensagens retidas na janela, não uma gravação contínua de toda a execução. São arquivos para consulta; não retomam processos, prompts pendentes ou conversas dos provedores. A versão antiga já em execução mantém seu comportamento anterior até ser encerrada.

## Boterm — inicialização dos provedores, 0.3.1 / build 18 (2026-11-13)

- Reproduzido no Claude instalado: `--mcp-config JSON PROMPT` consome o prompt longo como caminho de configuração e gera `ENAMETOOLONG`. Com `--mcp-config=JSON`, o mesmo prompt chega à configuração interativa inicial. Teste também passou pelo launcher compilado, com configuração isolada, sem enviar trabalho a um modelo.
- `python3 test/agent-launch.integration.py terminal/Boterm.app/Contents/Resources/bin/boterm`: quatro provedores, com/sem prompt e opções; configuração MCP por sessão, metacaracteres literais e ausência de execução do conteúdo do prompt. Socket e provedores substituídos apenas no teste.
- Gemini real aceitou a chamada do launcher com `--prompt-interactive` e `--help` (saída 0). Não foi validada uma conversa autenticada com Gemini.
- Harness nativo compilado com Swift 6: sete funções, diretório, prompts, opção interativa do Gemini, rejeição de pasta inválida e quatro tamanhos sem overflow aprovados. Usa o launcher real e substitui somente os executáveis dos provedores no bundle de teste. O limite inicial de 10 segundos expirou durante a partida das shells; a execução com 40 segundos passou e o teste agora permite esse intervalo.
- `npm test`: 27 testes aprovados. Unidade nativa aprovada: PTY real, resize, sanitização e ausência de envio sem Enter. Build 18 compilado, assinado com Developer ID e verificado com `codesign --verify --deep --strict`.
- Instalado em `/Applications/Boterm.app`, build 18; assinatura e teste dos quatro launchers repetidos no bundle instalado, ambos aprovados. Build anterior preservado em `work/development-check/Boterm-before-build18.app`; sessões existentes mantidas.

Sem ciclo autônomo completo com modelos, teste físico de microfone, push ou publicação nesta validação.

## Boterm — mosaico dos terminais, 0.3.1 / build 19 (2026-11-13)

- Botão Mosaico ao lado de Dividir: grade automática com todos os terminais do projeto ativo, colunas calculadas a partir do espaço disponível e seleção preservada ao voltar para uma única sessão. Não cria terminais nem reinicia processos. Altura mínima de 80 px por linha; janelas pequenas permitem rolagem vertical.
- Harness nativo com `VOZ_TEST_MODE=customize` e `VOZ_TEST_UI_SCRIPT=test/terminal-mosaic.js`: oito terminais, isolamento entre projetos, uma/duas/três colunas, troca de terminal sem desfazer a grade, transição com Dividir, estados acessíveis dos botões e preservação das instâncias aprovados. Quatro tamanhos (620×380, 800×600, 1440×900, 1120×720) aprovados; captura do mosaico inspecionada. Uma execução não concluiu a inicialização; repetida em cópia nova do bundle sem compilação concorrente, passou.
- `npm test`: 27 testes aprovados. Build 19 assinado com Developer ID, instalado em `/Applications/Boterm.app` e verificado com `codesign --verify --deep --strict`. Build 18 preservado em `work/development-check/Boterm-before-build19.app`; sessões existentes mantidas.

Sem novo teste físico de microfone, ciclo completo com modelos reais, push ou publicação.

## Verificação com provedores reais e envio ao GitHub (2026-11-13)

- Commits `7aa18cb` e `3424667` enviados para `origin/main`, com confirmação por `git ls-remote`. Nova instância do build 19 aberta; instância anterior e sessões do usuário preservadas.
- Teste interativo nativo em pasta temporária vazia, usando o launcher real: Claude recebeu um prompt maior que 255 caracteres, passou pela confirmação da pasta e respondeu corretamente ao cálculo 37 × 41 (`1517`). Não foi solicitado trabalho sobre arquivos do projeto nem alteração das permissões do CLI.
- Gemini abriu pelo launcher com `--prompt-interactive`, mas o login Google foi rejeitado com `This client is no longer supported for Gemini Code Assist for individuals`. Reproduzido também fora do Boterm com Gemini CLI 0.68.0, em pasta temporária, modo headless, código de saída 55. Não havia chave Gemini/Google API disponível no ambiente; valores de credenciais não foram lidos ou exibidos.
- O [comunicado oficial do Google](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/) informa a migração do acesso pessoal para Antigravity CLI e a continuidade do Gemini CLI para API paga e licenças empresariais. O bloqueio de autenticação do Gemini permanece; a escolha entre adicionar Antigravity e configurar acesso compatível foi apresentada ao usuário.

Esta verificação confirma uma resposta real do Claude e a inicialização do Gemini, não um ciclo completo de sete agentes com modelos reais. Nenhuma chave, conta ou cobrança foi criada.

## Gemini com login existente, 0.3.1 / build 20 (2026-11-13)

- Localizados `/Applications/Gemini.app` e `/opt/homebrew/bin/agy`. O terminal Antigravity já instalado está autenticado; não foi necessário instalar outro cliente nem iniciar login. O app Gemini de desktop permanece separado da integração por terminal.
- Adicionada a opção Gemini (Antigravity) ao seletor e às sete funções da equipe. Executa `boterm agent agy`, aceita estado do processo no controle local e usa `--prompt-interactive` para o prompt inicial. Mantém modelo, autenticação e permissões do cliente; não altera configurações globais ou configura chave de API. Gemini CLI permanece como opção separada.
- Teste real em pasta temporária: `agy --model gemini-3.8-flash-low --mode plan --print-timeout 45s --print ...` retornou `1517` para 37 × 41, saída 0. Variáveis Gemini/Google API ausentes e provedor de API por chave desativado na configuração existente.
- Harness nativo com launcher real e `agy` real: prompt inicial longo, resposta `1517`, estado Em execução e quatro tamanhos sem overflow aprovados. Captura inspecionada: Antigravity CLI 1.5.8, conta Google AI Pro e modelo Gemini 4 Argon (Medium). O teste não solicitou leitura, alteração de arquivos ou uso de ferramentas.
- `npm test`: 27 testes aprovados. Regressão dos cinco launchers aprovada. Harness das sete funções aprovado com Codex, Claude, Gemini CLI e Antigravity simulados, verificando diretório, prompts e modo interativo. Compilações de produção e de teste em Swift 6 concluídas; assinatura de produção verificada.
- Instalado em `/Applications/Boterm.app`, build 20; assinatura e regressão dos cinco launchers verificadas novamente no app instalado. Build 19 preservado em `work/development-check/Boterm-before-build20.app`. Nova instância aberta sem encerrar as sessões anteriores.

Sem novo teste de microfone nem ciclo completo de desenvolvimento com sete modelos reais. A integração validada usa a sessão local já autorizada, sem criar conta, chave ou cobrança por API.

## Equipe real, conversas e atenção — 0.3.1 / build 21 (2026-11-13)

- Ensaio descartável com sete funções reais: Orquestrador/Claude, Desenvolvimento/Gemini via agy, Testes/Codex, Integrações/Claude, UX/Gemini via agy, Engenharia de loop/Codex e Entrega/Claude. O Orquestrador criou o plano, atribuiu arquivos e enviou tarefas; Testes encontrou 19 falhas iniciais e reportou a reprodução ao dono. Gemini implementou a função e o reteste passou 19/19; Integrações revalidou 11/11 casos com a função real. Confirmações da pasta e leituras específicas foram autorizadas individualmente, sem alterar as permissões dos clientes.
- O primeiro controlador encerrou pelo limite de 1.000 segundos antes da conclusão de UX, revisão e entrega. A etapa final foi retomada com quatro sessões novas (Orquestrador, UX, Loop e Entrega), preservando o projeto e a propriedade dos arquivos. UX concluiu HTML/CSS e relatório; Loop aprovou os cinco critérios; Entrega repetiu os testes e consolidou EVIDENCIAS.md. O Orquestrador verificou e transmitiu BOTERM_CYCLE_COMPLETE. O marcador inicial veio acompanhado de um resumo; foi solicitado o marcador isolado para satisfazer a comparação estrita do controlador. Resultado final do harness: passed=true, completed=true, 17 mensagens na retomada. É um ensaio em duas etapas, não um ciclo ininterrupto ou prova de autonomia sem consentimentos.
- Verificação independente do operador: npm test no projeto descartável, 19/19; harness da UX repetido no Chrome headless isolado, conferindo que os quatro arquivos copiados eram idênticos aos reais. Iframe real de 390px: innerWidth=scrollWidth=clientWidth=390, também após erro; rótulo e aria-live presentes; foco visível de 3px no campo e botão; vazio, negativo e fração mostram erro, 3661→61:01 e 59→00:59; nenhuma exceção não tratada. A tentativa de janela headless de 390px foi descartada porque o Chrome impõe largura mínima de 500px. Playwright MCP sem ponte de extensão; usado o Chrome já instalado, sem novas dependências.
- Conversas espelhadas apenas nos painéis dos participantes, na cor do remetente, com nome e hora. Broadcast restrito ao projeto. Painel inferior contém só envio; transcrição duplicada removida após revisão visual do usuário. Texto de mensagem usa textContent; não vira HTML nem entrada do PTY. Linhas existentes são preservadas ao receber mensagens; só o histórico ativo anuncia novidades por aria-live. Retenção continua limitada às 200 mensagens da janela, incluídas uma vez no arquivo de histórico.
- Indicador de atenção usa a bolinha da sessão, pulsação e rótulo textual para menus e pedidos reconhecidos; marcador estático com movimento reduzido. Limpa após retorno ao compositor/saída e não responde às confirmações. Reconhecimento por padrões explícitos de CLI, sem garantia para formatos desconhecidos.
- npm test: 30/30. Harness nativo final de conversas: espelhamento, cores, isolamento, texto literal, linhas preservadas, atenção e limpeza, mosaico e ausência da transcrição inferior duplicada aprovados. Harness de personalização: cores, ordem por arraste, redimensionamento, nomes de projetos, processos preservados, compositor e tela cheia aprovados. Ambos passaram em 620×380, 800×600, 1440×900 e 1120×720. Uma execução reaproveitando o mesmo bundle expirou; as repetições em bundles de teste separados passaram.
- Regressão de histórico aprovada: arquivos privados e únicos, scrollback completo, mensagens, salvar antes de fechar, cancelar, falha de salvamento mantendo a sessão e descarte. Bundle de produção assinado com Developer ID e verificado.
- Instalado em `/Applications/Boterm.app`, build 21; assinatura e regressão dos cinco launchers aprovadas no bundle instalado. Build 20 preservado em `work/development-check/Boterm-before-build21.app`. Nova instância aberta, sem encerrar as instâncias e sessões anteriores do usuário.

Limites: sem novo teste físico de microfone ou leitor de tela; medição móvel em iframe headless, não em aparelho físico. O projeto descartável preserva uma nota documental antiga de Integrações, sinalizada nas evidências da equipe; não afeta o comportamento testado. Nenhum deploy do projeto descartável.

## Barra superior — 0.3.1 / build 22 (2026-11-13)

- Título nativo fixo Boterm, sem pasta, separador ou versão. Removida também a atualização do título ao abrir um diretório; histórico de projetos mantido. Versão 0.3.1 e build 22 disponíveis em Configurações/Sobre.
- Barra de título transparente sobre o fundo #090b10, igual ao cabeçalho de projetos. Mantidos controles nativos e aparência escura existente.
- Build Swift 6 concluído e assinatura Developer ID verificada no bundle de produção e em `/Applications/Boterm.app`. Build 21 preservado em `work/development-check/Boterm-before-build22.app`; nova instância aberta sem encerrar as anteriores.
- Inspeção visual não concluída: o serviço de controle da interface retornou `Sky Computer Use native pipe startup failed`, inclusive após reiniciar sua sessão. Não foram repetidos testes funcionais ou de microfone para esta alteração de título/aparência.

## Lateral, mosaico livre, perfis e Mensageiro — 0.3.2 / build 23 (2026-11-17)

- Causa do clique perdido na lateral: `renderNavigation` recriava linhas e abas a cada mudança de título dos agentes. Agora reaproveita os nós. Harness: 240 mudanças de título mantêm a mesma linha e o clique mostra o terminal escolhido.
- Mosaico livre (`test/terminal-mosaic.js`): redimensionar pelo canto e pelas setas, sem sobreposição, mover mantendo o tamanho, duplo clique repõe; perfil capturado, perfil corrompido ignorado e perfil reaplicado. Aprovado em 620×380, 800×600, 1440×900 e 1120×720.
- Preset (`test/terminal-development.js`, stubs de `launch20-stubs`): oito funções, Mensageiro em Claude por padrão, oito processos com diretório e prompts corretos, configurações do Mensageiro. A verificação de opacidade do lápis por `:focus-within` foi omitida nessa execução: a cópia de teste não fica ativa enquanto o usuário usa o Mac, e o WebKit só aplica foco em janela ativa.
- Mensageiro no socket real (`test/terminal-messenger.js`): sessão comum e sessão apenas renomeada Mensageiro recusadas em notify/grant; permissions legível por todos; ID desconhecido e canal não verificável recusados; Telegram sem emparelhamento informado. `test/messenger.unit.swift`: normalização, substituição, arquivo 0600, revogação e leitura das respostas.
- npm test: 30/30.

Limites: Telegram não testado ponta a ponta (sem bot configurado neste Mac). Envio e leitura de WhatsApp/email pelo agente não exercitados com modelo real. Nenhuma mensagem enviada para fora.
