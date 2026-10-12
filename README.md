<p align="center">
  <strong>Mellon</strong><br>
  <em>Speak friend, and control.</em>
</p>

Controle o seu Mac pelo iPhone na rede local. Trackpad, teclado e teclas de mídia, com um modelo
de segurança **um para um**: o seu Mac obedece só ao seu iPhone.

- **Pareamento por QR code.** Escaneie, confira o código de 6 dígitos e pronto. Sem senha, sem conta.
- **Só o seu iPhone.** Cada Mac confia em um único iPhone, autenticado por chaves Curve25519.
- **Criptografado de ponta a ponta.** TLS com chave pré-compartilhada e forward secrecy.
- **Nada sai da sua rede.** Sem servidor, sem nuvem, sem telemetria.

Os detalhes estão em [SECURITY.md](SECURITY.md).

## Recursos

- Trackpad: mover, tocar para clicar, dois dedos para rolar e para o botão direito, segurar para arrastar
- Teclado do iPhone digitando no Mac (qualquer idioma, independente do layout do Mac)
- Esc, Tab e setas
- Play/pause, faixa anterior/próxima, volume e mudo

## Requisitos

- macOS 14 ou mais recente
- iOS 17 ou mais recente
- Xcode 16 ou mais recente e [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Como rodar

```sh
brew install xcodegen
xcodegen generate
open Mellon.xcodeproj
```

1. Em cada target, escolha o seu time em *Signing & Capabilities* (uma conta Apple gratuita serve).
2. Rode o target **MellonMac**. O ícone aparece na barra de menus. Permita a Acessibilidade quando pedir.
3. Rode o target **MellonPhone** no seu iPhone (a câmera não funciona no simulador).
4. No Mac, clique em **Parear iPhone** e escaneie o código com o app.

## Estrutura

```
Packages/MellonCore   protocolo, criptografia, pareamento e transporte (com testes)
Apps/MellonMac        app de barra de menus que recebe os comandos
Apps/MellonPhone      app do iPhone
Apps/Shared           identidade visual compartilhada
```

Testes do núcleo:

```sh
cd Packages/MellonCore && swift test
```

## Licença

[MIT](LICENSE)

*Mellon não é afiliado ao espólio de J.R.R. Tolkien nem à Middle-earth Enterprises.*
