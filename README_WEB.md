# Testar o BLESSED no telemóvel (build Web)

O sandbox do Arena **não consegue** gerar o build Web (não pode descarregar o
motor Godot — CDN bloqueado). Faz isto na **tua máquina**, uma vez:

## 1. Pré-requisitos
- **Godot 4.7** (editor) instalado.
- **Export templates** instalados: no editor → `Editor → Manage Export Templates → Download`.

## 2. Exportar para Web
Pelo editor: `Project → Export → Web → Export Project` (já está configurado em
`export_presets.cfg`, com `thread_support=false` e compressão mobile).

Ou por linha de comandos (headless), na pasta do projeto:
```bash
godot --headless --export-release "Web" export/web2/index.html
```

## 3. Servir (com os headers que o Godot 4 exige)
```bash
python tools/serve_web.py export/web2 8060
```
Fica a escutar em `0.0.0.0:8060`.

## 4. Abrir no telemóvel
1. PC e telemóvel na **mesma rede Wi-Fi**.
2. Descobre o IP do PC (Windows: `ipconfig` → "Endereço IPv4"; ex.: `192.168.1.20`).
3. No browser do telemóvel: **`http://192.168.1.20:8060`** (usa o teu IP).

## Notas / problemas
- **Encaminha a porta 8060** no router se o telemóvel não conseguir ligar (ou usa
  o IP local; normalmente na mesma rede funciona sem port-forward).
- O projeto é **Forward+**. Em browsers móveis o Forward+ pode ser **pesado ou não
  arrancar** (iOS Safari, em especial). Se ficar lento/preto no telemóvel:
  `Project Settings → Rendering → Renderer → Rendering Method = "gl_compatibility"`,
  re-exporta e volta a servir. (No PC mantém Forward+.)
- `export/` deve estar no `.gitignore` — o build não vai para o Git.

## Controlos no ecrã
O jogo usa teclado/rato. Num telemóvel **não há** teclado/rato — para testar a sério
precisas de um comando Bluetooth ligado ao telemóvel, ou testa no PC. (Diz-me se
queres que adicione **botões virtuais na tela** — joystick + botões — para dar para
jogar no telemóvel.)
