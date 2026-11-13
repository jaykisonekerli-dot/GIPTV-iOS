# GIPTV para iPhone e iPad

Projeto nativo SwiftUI + AVKit/AVPlayer, iOS 16 ou superior. Este ZIP contém código-fonte e um projeto Xcode, não um instalador IPA.

## Abrir e instalar no seu iPhone

1. Em um Mac com Xcode 15 ou posterior, extraia o ZIP e abra `GIPTV.xcodeproj`.
2. Selecione o target GIPTV > Signing & Capabilities > sua equipe Apple. Se necessário, altere `com.jaykison.giptv.ios` para um identificador disponível na sua conta.
3. Escolha um simulador e compile primeiro. Também pode executar `bash validar-no-mac.sh`.
4. Conecte seu iPhone, selecione-o no Xcode e use Run. Siga os pedidos do Xcode para assinatura e modo de desenvolvedor.
5. Para distribuição a outras pessoas, use Archive e o fluxo autorizado da Apple para TestFlight, App Store ou dispositivos registrados. A conta, os certificados e a aprovação não estão incluídos neste projeto.

## Implementado no código

- Login Xtream: servidor, usuário e senha; reconexão ao iniciar com acesso salvo no Keychain.
- Início com TV, filmes e séries; categorias, busca, grade compacta com capas e rolagem contínua.
- Temporadas em abas horizontais; episódios ordenados por número.
- Favoritos separados por tipo; pressione uma capa ou use a ação nos episódios.
- Últimos 60 abertos, sem duplicatas, por conta; toque para reproduzir.
- Posição salva a cada 5 segundos e ao sair/pausar; opção de reiniciar.
- Player nativo com play/pause, busca no tempo e apresentação em tela cheia; rotação do aparelho.
- Barra do app oculta após 4 segundos de reprodução; controles nativos têm comportamento próprio do iOS.
- Tentativas de reconexão após falha e atualização integral do catálogo com preservação em caso de erro.
- Programação do servidor quando disponível; resumo quando presente no catálogo/API.
- Exclusão de dados locais e saída de conta.

## Limites importantes

Não há Mac, Xcode, SDK iOS ou dispositivo Apple neste ambiente Windows. Não foi executada compilação Swift, assinatura, simulador ou teste físico. A validação feita aqui cobre integridade do pacote, referências do projeto, plists, esquema Xcode e recursos; erros de compilação ou de execução ainda podem precisar de correção no Xcode. Não há IPA produzido nem publicação na App Store.

TV ao vivo usa HLS/M3U8. Arquivos VOD usam o formato fornecido pelo serviço. AVPlayer não reproduz universalmente todos os codecs/contêineres de IPTV: MPEG-TS direto, MKV ou codecs incompatíveis podem exigir HLS/MP4 do provedor. Sem transcodificação ou VLC embutido.

O player usa os controles nativos do iPhone; os gestos não são uma cópia exata das versões Windows/Android. Não há sincronização de favoritos ou histórico entre plataformas. O app não fornece conteúdo nem contas.

## Privacidade e revisão para distribuição

Credenciais no Keychain, com acesso local ao dispositivo desbloqueado. Favoritos, recentes e progresso em UserDefaults por hash do servidor/usuário. Sem analytics ou publicidade. API, imagens e mídia vêm do servidor selecionado. HTTP está permitido por solicitação do usuário e trafega sem criptografia; prefira HTTPS. A validação de certificados HTTPS não foi desativada.

O manifesto de privacidade inclui UserDefaults para preferências do app (CA92.1). Antes de publicar, confirme declarações de dados para os servidores realmente usados, justificativa das exceções de rede, licença do conteúdo, dados de revisão, screenshots e todas as exigências atuais da Apple. O manifesto não constitui aprovação de publicação.

## Referências oficiais

- https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html
- https://developer.apple.com/streaming/
- https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest

## Verificação manual no Mac

Compile primeiro sem assinatura no simulador. Teste login válido/inválido, servidor indisponível, HTTP/HTTPS, voltar ao app, temporadas 1/2/10, favoritos por tipo, recentes, atualização com falha, HLS real autorizado, pausa/retomada após encerrar app, áudio/interrupções, rotação, exclusão de dados e limite final do vídeo. Use somente servidores e conteúdos autorizados.
