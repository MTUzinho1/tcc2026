# BookShare — Biblioteca escolar

**Uma biblioteca organizada, sem complicação.**  
Aplicação web desenvolvida como trabalho de conclusão de curso, com foco em uma experiência acolhedora e fácil para profissionais de bibliotecas escolares.

**Acesse:** https://tcc2026.onrender.com

## O que o sistema faz

O BookShare tem uma landing page pública e uma área privada acessível aos perfis **administrador** e **bibliotecária**. O fluxo do dia a dia foi organizado em ações grandes: **Fazer empréstimo**, **Registrar devolução**, **Cadastrar livro** e **Cadastrar aluno**.

- **Início:** quatro ações rápidas, resumo do acervo e devoluções próximas.
- **Empréstimos:** localizar aluno e exemplar com busca, escolher vencimento, confirmar retirada; renovar empréstimos ativos.
- **Devoluções:** procurar pelo aluno, título ou código e registrar condição do exemplar.
- **Livros:** consultar capas, buscar por título/autor/ISBN, cadastrar e editar obras, adicionar exemplares.
- **Alunos:** pesquisar, cadastrar, editar, atualizar situação e anexar fotos autorizadas.
- **Reservas:** solicitar, disponibilizar, retirar ou cancelar.
- **Relatórios:** indicadores, empréstimos por mês, livros mais emprestados e impressão.
- **Equipe (administrador):** listar e cadastrar funcionários com os perfis permitidos.
- **Conta:** login, logout e alteração de senha.

## Tecnologias

- Frontend: HTML5, CSS3 e JavaScript.
- Backend: Node.js, Express, JWT com cookie HTTP-only e bcrypt.
- Banco: PostgreSQL/Supabase, schema privado `bookshare_v2`.
- Infraestrutura: Render para a aplicação; GitHub Pages encaminha para o serviço.
- QA: Node.js Test Runner, PostgreSQL de integração e Playwright (Chromium desktop e mobile).

## Estrutura

```
index.html                      Redireciona para o sistema hospedado
server.js                       Entrada para a API V2
bookshare-v2/
  public/index.html             Landing, login e interface da biblioteca
  public/styles.css             Sistema visual verde e responsivo
  public/app.js                 Eventos, busca e comunicação com API
  src/server.js                 Rotas e autenticação
  src/flows.js                  Regras de empréstimo, devolução e reservas
  schema.sql                    Tabelas do schema privado
  tests/                        Testes de regras, API e navegação real
```

## Execução e testes

Para desenvolvimento, use um **PostgreSQL de testes**, nunca o banco ativo da escola. Consulte `bookshare-v2/README.md` para as variáveis necessárias e instalação.

```bash
cd bookshare-v2
npm install
npm run check
npm test
npm start
```

O workflow **BookShare V2 - revisão automatizada** executa cenários reais com PostgreSQL e Chromium.

## Responsabilidade com os dados

- Não publique senhas, segredos de banco nem fotografias de alunos sem autorização.
- O backend valida permissões e operações de escrita.
- A versão antiga foi preservada na branch `bookshare-v1-backup-antes-da-v2`.
- As fotos dos alunos precisam ter uso autorizado. Capas de terceiros devem respeitar as respectivas licenças.
