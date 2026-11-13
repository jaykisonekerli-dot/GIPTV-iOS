# Compilar o GIPTV pelo GitHub, usando Windows

O projeto precisa estar na raiz do repositório: GIPTV.xcodeproj, GIPTV, .github e demais arquivos no mesmo nível. Não envie somente o ZIP.

1. Crie um repositório separado chamado GIPTV-iOS em sua conta. Público significa que qualquer pessoa poderá ver e baixar o código; privado usa sua cota gratuita de Actions e pode cobrar excedentes conforme sua conta.
2. Envie os arquivos extraídos deste pacote, incluindo a pasta .github. Não envie senhas, certificados ou dados de servidores.
3. Abra Actions > Compilar GIPTV iOS (sem assinatura) > Run workflow.
4. Aguarde a execução. Se falhar, abra a etapa vermelha e envie o log de compilação para correção.
5. Em Artifacts, baixe GIPTV-compilacao-sem-assinatura. O ZIP do simulador é para um simulador Apple, não para instalar no iPhone.

O fluxo roda somente quando iniciado manualmente, usa um executor macOS padrão, tem limite de 20 minutos e guarda os resultados por 3 dias. Não instala certificados, não acessa sua Conta Apple e não publica nada na App Store.

Ainda não foi executado. O projeto Swift não foi compilado neste ambiente Windows. A primeira execução é necessária para identificar e corrigir erros de compilação.

Para distribuir no iPhone, existe uma etapa posterior de assinatura Apple e provisionamento. Um build sem assinatura não equivale a um IPA instalável.

Referências:
https://docs.github.com/en/actions/concepts/billing-and-usage
https://developer.apple.com/help/account/membership/programs-overview
