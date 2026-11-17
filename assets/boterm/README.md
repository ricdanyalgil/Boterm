# Boterm — conceito de identidade

Nome escolhido por Ricardo em 13/11/2026. Conceito selecionado como ícone do aplicativo Boterm 0.3.0; exportação ICNS em terminal/Boterm.icns.

`icon-concept.png`: dois balões conectados formam o símbolo de terminal `>_`. Verde menta, conexão azul e base escura. O desenho não contém texto e pode ser usado com o nome Boterm.

Gerado com a ferramenta integrada Imagegen; não foi usado o CLI de fallback. O prompt usava o nome provisório Bot Terminal, anterior à escolha de Boterm; como o ícone não contém palavras, não foi necessária uma nova geração.

## Prompt utilizado

Use case: logo-brand. Asset type: provisional macOS application icon concept for Bot Terminal, a multi-terminal workspace where AI coding agents collaborate and users dictate prompts. Primary request: one beautiful, simple, instantly recognizable app icon, centered large on an actual transparent background. A near-black rounded-square macOS icon tile contains a mint-green stylized terminal prompt >_ cleverly formed as two connected speech shapes, suggesting agents exchanging messages. One small soft blue connection accent. Sophisticated clean geometric design, restrained flat vector-like treatment, extremely legible at Dock size, balanced generous inner padding. No words, no letters, no robot face, no mascot, no 3D mockup, no surrounding props, no extra tiles. The tile is opaque; everything outside it truly transparent.

## Ícone profissional — build 14

`icon-professional.png` substitui o conceito anterior no aplicativo. Base quase preta com borda discreta e símbolo de terminal >_ em verde menta; geração integrada Imagegen, transparência preservada. Exportado para terminal/Boterm.icns em 16–1024 px; inspeção visual em 64 px.

Prompt: Use case: logo-brand. Asset type: final macOS application icon for Boterm, a professional terminal and collaborative coding app. Create ONE square 1024x1024 app icon, centered, perfectly front-facing, no scene or mockup. Near-black rounded macOS squircle tile with a restrained satin finish and subtle edge definition, filling 90% of canvas. Surrounding area truly transparent. Center a beautifully proportioned, large, simple terminal prompt glyph >_ in pale luminous mint, clear geometry, optically balanced, generous negative space. The chevron and short underscore form one coherent mark. The design should feel like a premium native developer tool, understated, crisp and immediately legible in a 32px Dock icon. Preserve the spirit of an older black-and-mint terminal icon but improve proportions and refinement. No chat bubbles, robots, letters, words, decorative circuitry, additional symbols, tiny details, dramatic glow, metallic bevels or perspective. Exactly one standalone icon.

## Ícone da Grelha construída — 17/11/2026

`icon-grid.svg` (fonte) e `icon-grid.png` (1024 px, render do Chrome headless com fundo transparente) substituem o ícone profissional no aplicativo, alinhando-o ao mundo visual Grelha construída. É o `>_` em giz (#e8e9ec) sobre base quase preta, construído célula a célula sobre a grelha de construção azul, com uma célula laranja no lugar do cursor. Foi desenhado à mão em SVG, sem ferramenta de geração de imagem. Exportado com `terminal/build-icon.sh`; legibilidade conferida a 32 px.

## Banner do README — 17/11/2026

`banner.png` (2560×1280) é a capa do README e a imagem de pré-visualização social do repositório. Fonte em `banner.html`, que usa `icon-grid.svg`, a Saira do app e `screens/grid-mosaic.png`. As três capturas em `screens/` vêm do harness nativo com dados de exemplo, reduzidas para 1600 px. Para regenerar a partir desta pasta:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
  --allow-file-access-from-files --force-device-scale-factor=2 --window-size=1280,640 \
  --screenshot="$PWD/banner.png" "file://$PWD/banner.html"
```
