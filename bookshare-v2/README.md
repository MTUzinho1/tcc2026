# BookShare V2 — reconstrução

Versão independente para substituir gradualmente o BookShare antigo. **A branch main e o banco de produção antigo não são alterados.**

## Identidade
Interface redesenhada do zero: tipografia editorial, verde profundo e fundo creme, navegação consistente para administração e biblioteca, telas responsivas.

## O que está implementado no código
- Login e logout usando cookie HTTP-only, SameSite Strict, JWT com validade de 8 horas, verificação de origem em operações de escrita
- Cadastro e edição de alunos, com foto opcional
- Cadastro de obras, capas próprias e exemplares físicos com código individual
- Empréstimo com transação SQL e trava do exemplar para evitar empréstimos simultâneos
- Devolução com atualização transacional do estado da cópia, incluindo danificado/extraviado
- Renovação com limite de duas vezes
- Reservas e mudança de status; painel de indicadores e vencimentos
- Contas para administradores e bibliotecárias; upload de foto/capa redimensionada para WebP

**Atenção:** isto é uma base inicial da reconstrução, não um sistema homologado. O fluxo real ponta a ponta e o visual em dispositivos distintos ainda precisam de testes com banco PostgreSQL, dados de demonstração e navegador. Não conecte o banco antigo sem planejar migração.

## Instalação local
1. Instale Node.js 20+, PostgreSQL e crie um banco de desenvolvimento **novo**, por exemplo `bookshare_v2`.
2. Execute o arquivo `schema.sql` somente nesse banco. Ex.: `psql "$DATABASE_URL" -f schema.sql`.
3. Copie `.env.example` para `.env` e configure `DATABASE_URL`, `JWT_SECRET` (32+ caracteres), `APP_ORIGIN=http://localhost:3000`, `BOOTSTRAP_ADMIN_EMAIL`, `BOOTSTRAP_ADMIN_PASSWORD` (12+ caracteres).
4. Entre na pasta `bookshare-v2` e rode `npm install`, `npm run check`, `npm test` e `npm start`.
5. Abra `http://localhost:3000` e faça login com o administrador inicial.

O bootstrap só cria o primeiro administrador quando a tabela `users` ainda está vazia; outras contas são criadas pela tela **Equipe**.

## Critérios para liberar a nova versão
- Executar testes manuais completos no navegador: login; aluno; livro; capa; exemplar; empréstimo; devolução normal; devolução danificada; empréstimo duplicado; renovação; reserva e cancelamento
- Testar sessões expiradas, erro de API e de banco, imagens inválidas, dispositivos móveis, acessibilidade e permissões
- Conferir concorrência de operações, integridade das reservas e consultas com mais de 100 registros
- Criar relatórios, trilha de auditoria, regras de prazo configuráveis, importação/migração, políticas de proteção dos dados escolares e testes de integração antes de produção
- Implantar em uma hospedagem de teste; **não** alterar imediatamente o GitHub Pages ou o Render antigos

### Fotos de alunos e capas
A V2 aceita **upload local opcional**, não usa fotos reais de estudantes automaticamente e não importa imagens protegidas de terceiros. Use consentimento e cuidado com dados pessoais dos alunos; para apresentação, prefira dados fictícios e imagens autorizadas.

### Estrutura
```
bookshare-v2/
  public/index.html
  public/styles.css
  public/app.js
  src/server.js
  src/flows.js
  tests/flows.test.js
  schema.sql
  package.json
  .env.example
```
