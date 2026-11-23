# BookShare V2 — Interface verde acolhedora

Esta é a implementação ativa do BookShare. Foi reconstruída para funcionar de maneira simples com profissionais de biblioteca escolar, sem depender de conhecimento técnico.

## Experiência de uso

Uma landing page explica o produto, seguida de login simples, dashboard com quatro tarefas principais e páginas objetivas. Os botões são grandes, os formulários têm rótulos visíveis e a busca por aluno/exemplar evita centenas de opções difíceis de percorrer.

O visual usa tons de verde-floresta, branco, áreas de respiro e boa hierarquia tipográfica. Há layouts de desktop e celular.

## Funcionalidades implementadas

Login, logout, atualização de senha, indicadores, cadastro e edição de aluno/livro, upload de imagens, exemplares, empréstimos, renovações, devoluções, reservas e relatórios agregados. Operações de retirada e devolução usam transações PostgreSQL e limites de integridade para impedir empréstimos duplicados.

A API não depende da interface para validar permissões, datas e estados.

## Preparar ambiente de desenvolvimento

1. Instale Node.js 20+ e PostgreSQL.
2. Crie um **banco novo de testes**, separado da produção.
3. Execute `schema.sql` como usuário autorizado do banco.
4. Copie `.env.example` para `.env`. Configure `DATABASE_URL`, `JWT_SECRET` com pelo menos 32 caracteres, `APP_ORIGIN` exata, `BOOTSTRAP_ADMIN_EMAIL` e `BOOTSTRAP_ADMIN_PASSWORD` (mínimo de 12 caracteres).
5. Instale as dependências com `npm install`.
6. Rode `npm run check` e `npm test`.
7. Rode `npm start` e abra `http://localhost:3000`.

O bootstrap cria o administrador apenas se a tabela de usuários está vazia.

## Testes automatizados

O workflow `.github/workflows/bookshare-v2.yml` inicia PostgreSQL, instala Node e Chrome e executa as suítes com Playwright.

Os cenários incluem:

- Autenticação, origem de requisições, perfis e atualização de senha.
- Alunos, livros, exemplares, fotos e capas.
- Empréstimos simultâneos, devolução normal/danificada e renovações.
- Reserva e retirada, integridade de registros, busca e relatórios.
- Fluxo real no navegador, landing, login, painel, cadastro, empréstimo, devolução, relatório e layout móvel.

## Produção

O Render está configurado para iniciar pelo arquivo `server.js` da raiz, que importa `bookshare-v2/src/server.js`. O GitHub Pages encaminha a URL anterior para a aplicação.

A V2 usa o schema `bookshare_v2` no Supabase. O schema público legado é mantido separado.

Nunca grave credenciais no código. Configure-as no serviço de hospedagem. Troque senhas iniciais que já tenham sido publicadas. Revise autorização de imagem de alunos, logs, backups e política de privacidade antes de usar com dados escolares reais.
