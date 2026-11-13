# Boterm: pesquisa e proposta de evolução

13/11/2026. Pesquisa original e direção de implementação. Em 13/11/2026 Ricardo autorizou implementar Boterm. A versão 0.3.0 implementa abas por projeto, sessões laterais, splits e comunicação local por CLI. O guia de uso atual está em AGENT_GUIDE.md e terminal/README.md; os trechos abaixo registram o diagnóstico anterior à implementação. Não houve renomeação remota do GitHub.

## O projeto lembrado como “raace”

O candidato mais forte pelo nome é [RACE](https://race-term.com/), abreviação de Run Anything in Canvas Environment. O site oficial foi consultado diretamente por HTTP porque a ferramenta de navegação não conseguiu abri-lo. Ele descreve um canvas com terminais móveis, agrupamentos, espelhos e sessões em hosts PTY separados que continuam após reiniciar a interface. O servidor `race-mcp`, habilitado pelo usuário, permite a agentes ler e enviar entrada aos terminais e controlar o canvas. O utilitário `race-control` oferece controle por scripts.

Isso corresponde à ideia de agentes observarem e operarem sessões visíveis. Não comprova que o produto visto pelo colega era esse, nem que existe uma conversa automática entre quaisquer agentes sem configuração. [Vídeo citado pelo autor](https://www.youtube.com/watch?v=8AL50dHCznA). O vídeo não foi assistido nesta pesquisa.

O melhor candidato pelo formato de abas é [cmux](https://cmux.com/), com [código no GitHub](https://github.com/manaflow-ai/cmux): aplicativo nativo macOS com barra lateral de workspaces, painéis divididos, abas, notificações e API/CLI de controle. É uma referência de organização visual. Sua [licença](https://raw.githubusercontent.com/manaflow-ai/cmux/main/LICENSE) distingue o núcleo GPL de diretórios de servidor com licença própria; incorporar código exige avaliar os arquivos efetivamente usados.

[RMUX de Helvesec](https://github.com/Helvesec/rmux), disponível em [rmux.io](https://rmux.io/), é uma referência para automação: multiplexer persistente com SDKs em Rust, Python e TypeScript, captura de tela textual e sincronização de saída. O projeto disponibiliza [licença MIT](https://raw.githubusercontent.com/Helvesec/rmux/main/LICENSE-MIT). Não confundir com outros repositórios também chamados rmux. Nenhum desses produtos foi instalado ou testado nesta pesquisa.

## O que existe hoje no VozTTY

Verificado no checkout `/Users/ricardodanyalgiljunior/Softwares/VozTTY`, com remoto `https://github.com/ricdanyalgil/VozTTY` e árvore inicialmente limpa:

- `terminal/App.swift`: `AppDelegate.terminals` mantém várias janelas; cada `TerminalWindow` possui `ShellSession`, `WKWebView` e ditado próprios. A ponte WebKit encaminha entrada, redimensionamento e títulos para aquela sessão.
- `terminal/PTY.swift`: PTY real com saída e encerramento, atualmente pertencente à janela. Não há daemon de sessões persistentes.
- `terminal/web/terminal.js` e `index.html`: um renderizador xterm por janela; o layout ainda não possui árvore de workspaces, abas ou splits.
- `terminal/Dictation.swift` e o helper nativo mantêm o ditado local. A inserção passa pelo renderizador e não envia Return.
- `terminal/build.sh`: versão de fonte 0.2.9, identidade `com.danyalgil.voztty.terminal`, executável e bundle VozTTY.
- `package.json` e `extension.js`: extensão VS Code separada. A mudança da identidade do app nativo não precisa mudar os identificadores públicos da extensão.

`terminal/README.md` conserva trechos antigos que dizem sessão única, apesar da seção posterior sobre várias janelas. Atualizar isso junto da documentação da próxima implementação. A versão instalada não foi auditada nesta pesquisa.

## Direção recomendada

Evoluir a base Swift/AppKit + xterm existente. Usar RACE como referência para controle de sessões e cmux para navegação, mantendo o ditado local como diferencial. Nenhum código externo foi copiado ou dependência adicionada. Não escolher agora uma migração de motor de terminal: não é necessária para implementar abas.

Layout proposto:

```text
Boterm     [Projeto A] [Projeto B] [+]                [Ditar]
┌────────────────┬──────────────────────┬────────────────────┐
│ Sessões        │ Codex                │ Claude             │
│ ● Coordenador  │ terminal real        │ terminal real      │
│ ● Codex        │                      │                    │
│ ◌ Claude       ├──────────────────────┴────────────────────┤
│ ○ Testes       │ Equipe: mensagens, decisões e entregas    │
└────────────────┴───────────────────────────────────────────┘
```

Abas superiores representam projetos/workspaces. A lateral lista terminais e agentes daquele projeto. O centro pode dividir sessões lado a lado. “Equipe” mostra mensagens com remetente, destinatário, horário e tarefa. Estados devem vir de eventos conhecidos; saída silenciosa não comprova que um agente terminou.

## Menor implementação completa

1. Separar sessão de janela: cada sessão conserva PTY, renderizador, diretório e título ao trocar de aba. Uma janela passa a hospedar várias sessões; trocar o foco não reinicia o shell. Nova aba, renomear, fechar e alternar por teclado; conservar nova janela.
2. Adicionar a navegação por workspace e sessão, mais uma divisão horizontal/vertical simples. Fechar sessão ativa continua pedindo confirmação. Fechar uma aba não pode encerrar outra.
3. Expor controle local de sessões por um socket Unix restrito ao usuário e ao workspace. Operações mínimas: listar, ler saída limitada, criar sessão, enviar mensagem e consultar mensagens. Um adaptador MCP fornece essas ferramentas aos CLIs compatíveis. Mensagem de equipe é um evento estruturado, não texto automaticamente digitado em qualquer shell.
4. Ligar dois agentes reais ao mesmo workspace e exibir um diálogo de pedido, revisão e resposta. O coordenador é um agente usando as mesmas ferramentas; o terminal oferece transporte e visibilidade. A integração precisa ser configurada em cada CLI e comprovada com um teste real.
5. Aplicar a marca Boterm ao app nativo, menus, bundle exibido, ícone e documentação. Manter o endereço do GitHub inicialmente; uma renomeação remota pode ser feita depois sem ser requisito para a marca do aplicativo.

Mensagens devem ter ID, referência à tarefa e destinatário para evitar respostas duplicadas e ciclos de conversa. Limitar tamanhos e reter apenas o necessário. Leitura entre sessões fica restrita às sessões explicitamente compartilhadas com a equipe. Saída de terminal é conteúdo não confiável, nunca uma instrução de controle. A API não deve transformar uma leitura em execução de comando.

Separar envio de mensagem, inserção de texto e submissão ao processo. O ditado e anexos continuam inserindo rascunho sem Enter. Uma operação explícita de execução pelo agente é diferente e deve aparecer no registro. Tokens, senhas e saídas de sessões particulares não devem ser compartilhados por padrão. Evitar uma porta de rede nesta primeira versão.

## Alcance da alteração e verificação necessária

| Área | Onde deve chegar | Evidência necessária |
| --- | --- | --- |
| Sessões e navegação | `terminal/App.swift`, `PTY.swift`, renderizador e estilos | alternar abas mantém PID, conteúdo, diretório e entrada; fechar afeta somente a sessão escolhida |
| Ditado e anexos | `Dictation.swift`, callbacks de foco, drop e painel de voz | gravar numa sessão e alternar de aba não insere texto na sessão errada; nenhum Enter automático |
| Layout | `terminal/web`, atalhos e acessibilidade nativa | foco por teclado, redimensionamento, 620–1440 px, painel estreito e movimento reduzido |
| Comunicação | novo controle local, adaptador e painel de equipe | dois agentes trocam pedido/resposta; isolamento entre workspaces, destinatário inválido e limites de entrada |
| Marca | `terminal/build.sh`, `App.swift`, título HTML, ícone, READMEs | nome no Finder/menu/Dock; assinatura e permissões preservadas com a identidade estável |
| Harness e fixtures | `test/terminal.unit.swift`, `test/terminal.integration.swift`, testes JS afetados | atualizar o harness que hoje assume uma janela/sessão; manter regressões de PTY, paste e ditado |
| Distribuição | scripts de build/empacotamento e referências aos artefatos | nomes de app/ZIP consistentes, assinatura verificável e pacote testado antes de substituir a instalação |

Manter inicialmente bundle identifier, chaves de preferências, `window.voz`, comandos `voz.*` e helper: são identificadores técnicos existentes e não precisam acompanhar a marca pública. Revisar os caminhos de recursos antes de renomear executável ou bundle. Não encerrar as sessões que Ricardo já está usando para instalar uma versão nova.

Persistência de processos após fechar o aplicativo exige separar o host PTY do processo da interface; salvar apenas o layout não preserva um agente rodando. Essa capacidade fica para uma etapa própria, sem promessa de sobrevivência a reboot. Cloud, acesso remoto e canvas infinito também ficam fora da primeira versão.

## Identidade

**Boterm**, nome escolhido por Ricardo. Conceito em `assets/boterm/icon-concept.png`, com prompt e procedência no README da mesma pasta. Dois balões ligados formam `>_`, verde menta com conexão azul sobre base escura. O arquivo é um conceito raster; ainda precisa de exportação ICNS e conferência nos tamanhos do Dock antes de substituir o ícone publicado.

A busca preliminar não confirmou outro terminal de software com o nome Boterm; isso não é uma verificação de disponibilidade de marca ou domínio. Não houve renomeação do GitHub, instalação, publicação ou alteração do código de execução nesta etapa.
