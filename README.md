# CONSART Entradas

App Flutter (Android e iOS) para lançar notas fiscais de entrada (NF-e de
fornecedores) no ERP Infinity (https://erp.consart.com.br), usando as mesmas
APIs da tela **Notas de Entrada** do ERP.

## Funções

- Login com o usuário do ERP
- Lista de notas de entrada: busca (chave, número, CNPJ, fornecedor), período,
  ordenação, situação (pendente / lançada)
- Nota lançada: dados, itens com produto e lote, parcelas, DANFE e XML, excluir
  (o ERP estorna estoque e contas a pagar)
- Nova entrada por:
  - **Caixa DF-e** (notas da SEFAZ), com envio da Ciência da Operação quando
    só o resumo está disponível
  - **Código de barras da DANFE** (câmera lê a chave de 44 dígitos)
  - **Arquivo XML** do aparelho
- Fornecedor não cadastrado: cadastro rápido com CNPJ e razão social do XML
- Conferência: vínculo de cada item a um produto (busca ou leitor), lote
  quando o estoque usa lote, dados da nota e parcelas (contas a pagar)
- **Salvar e lançar**: grava a nota, cria as contas a pagar e dá entrada no estoque

## APK

Cada push na `main` gera um APK pelo GitHub Actions. Último APK:
https://github.com/consartAdmin/inbound-invoices-app/releases/latest/download/consart-entradas.apk
