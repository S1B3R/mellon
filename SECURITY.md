# Segurança do Mellon

O Mellon controla o seu Mac. Por isso a segurança vem antes de qualquer recurso. Este documento
descreve o modelo de ameaças e como o app se protege. O código correspondente está em
[`Packages/MellonCore`](Packages/MellonCore).

## Princípios

1. **Um para um.** Um Mac confia em exatamente um iPhone. Parear um novo iPhone revoga o anterior.
2. **Sem servidor.** Tudo acontece na rede local. Não há conta, nuvem nem telemetria.
3. **Lista fechada de comandos.** O Mac só entende mover o mouse, clicar, rolar, teclas, texto e
   teclas de mídia. Nada vindo da rede executa shell, scripts ou abre arquivos.
4. **Controle visível.** O ícone na barra de menus mostra quando o iPhone está conectado, e
   "Pausar controle" corta o acesso na hora.

## Como funciona

### Identidade
Cada aparelho gera um par de chaves Curve25519 na primeira execução. A chave privada fica no
Keychain com `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: não sincroniza com o iCloud e não
é restaurada em outro aparelho a partir de um backup.

No Mac, isso vale quando o app é assinado com um Team ID da Apple (o Keychain de proteção de
dados exige essa assinatura). Em builds sem time, o app usa o Keychain de login: a chave continua
cifrada e protegida por ACL, mas `ThisDeviceOnly` não se aplica. Para uso real, assine o app.

### Pareamento
1. O Mac gera um convite com sua chave pública, um **segredo aleatório de 256 bits** de uso único,
   um nome de serviço Bonjour aleatório e uma validade de 2 minutos. O convite aparece como QR code.
2. O Mac abre um listener temporário (`_mellon-pair._tcp`) protegido por TLS-PSK. A chave é
   derivada do segredo do convite com HKDF-SHA256.
3. O iPhone escaneia o QR code e conecta. O handshake só termina se os dois conhecem o segredo.
   O iPhone então envia o nome e a chave pública dele.
4. Os dois mostram um **código de 6 dígitos** derivado das duas chaves públicas. O usuário confere
   e clica em "Permitir" no Mac.
5. O Mac guarda a chave do iPhone, responde com um nome de serviço aleatório para as sessões e
   fecha o listener de pareamento.

O QR code é um canal fora da rede: quem está no mesmo Wi‑Fi não vê o segredo e não consegue se
colocar no meio da conexão.

Convites que chegam por um link `mellon://` aberto de fora do app (mensagem, página, câmera do
sistema) **não são aceitos automaticamente**: o iPhone pede confirmação antes de parear e avisa se
isso substitui o Mac atual. Sem isso, qualquer pessoa na mesma rede poderia mandar um link para um
Mac dela, aprovar o pedido do próprio lado e passar a receber o que você digita. O nome do Mac no
link é informado por quem o gerou e não é verificado. Os QR codes lidos pelo leitor dentro do app
pareiam direto, porque você acabou de pedir o código no seu Mac.

### Sessões
- A chave de sessão é `HKDF(ECDH(chave privada própria, chave pública do par))`, ligada às duas
  chaves públicas. Só os dois aparelhos pareados conseguem calculá-la.
- O transporte é TLS 1.2 com a suíte `TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256` (RFC 7905):
  autenticação mútua pela PSK e **forward secrecy** pelo ECDHE efêmero. O canal recusa a conexão
  se qualquer outra suíte for negociada.
- Nada é lido da conexão antes do handshake terminar. Conexões que não completam o handshake em
  10 segundos são derrubadas.
- O Mac aceita conexões só de endereços locais (IPv4 privados, link-local, loopback e IPv6
  unique-local), limita novas conexões por minuto e recusa mensagens maiores que 64 KB.

## Limitações conhecidas

- Quem tem acesso físico ao Mac desbloqueado pode parear outro iPhone. Isso é intencional: o dono
  do Mac é a autoridade.
- O app de Mac roda fora do App Sandbox, porque a permissão de Acessibilidade exige isso.
- Esquecer o Mac no iPhone não revoga o acesso no Mac. Use "Esquecer iPhone" no Mac para isso.
- A lista fechada impede comandos *pela rede*, mas o iPhone pareado é um teclado e um mouse: ele
  pode digitar um comando num Terminal aberto e apertar Return. Ter o iPhone pareado equivale a
  ter acesso ao teclado do Mac.
- O app do iPhone não tem trava própria (como Face ID). Quem pegar o iPhone desbloqueado consegue
  controlar o Mac enquanto ele estiver na mesma rede. Use "Pausar controle" ou "Esquecer iPhone"
  no Mac se perder o aparelho.

## Como reportar uma vulnerabilidade

Não abra uma issue pública. Use o recurso de *Private vulnerability reporting* do GitHub neste
repositório. Responderemos assim que possível.
