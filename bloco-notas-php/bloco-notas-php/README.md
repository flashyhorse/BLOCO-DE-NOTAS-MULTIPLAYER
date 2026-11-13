# Bloco de Notas Compartilhado — PHP + PostgreSQL

CRUD web do projeto **Senai Joinville**, escrito em PHP puro (sem framework) sobre PostgreSQL.
O código foi organizado para ser **lido de cima para baixo** e **alterado em poucos lugares**:
cada arquivo começa com um comentário dizendo o que faz, qual requisito (RF/RN) atende e como adaptar.

## 1. Requisitos

| Item | Versão |
|---|---|
| PHP | 8.0 ou superior, com as extensões **pdo_pgsql** e **mbstring** |
| PostgreSQL | 12 ou superior |

Verificar: `php -m | grep -E "pdo_pgsql|mbstring"` (Windows: `php -m | findstr /i "pgsql mbstring"`).
Se faltar alguma, abra o `php.ini` e remova o `;` das linhas `extension=pdo_pgsql` e `extension=mbstring`.

## 2. Instalação (uma vez)

```bash
# 1) criar o banco
psql -U postgres -c "CREATE DATABASE bloco_notas ENCODING 'UTF8'"

# 2) criar tabelas, funções, triggers e views
psql -U postgres -d bloco_notas -f banco/schema.sql

# 3) ajustar usuário/senha do banco em config/config.php
#    (ou use as variáveis de ambiente DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS)

# 4) (opcional) dados de exemplo — senha de todos: senha1234
php banco/semear.php
```

## 3. Executar

```bash
php -S localhost:8000 -t public
```

Abra <http://localhost:8000>. Logins de exemplo: `admin@senai.exemplo`, `maria@senai.exemplo`, `joao@senai.exemplo`.

## 4. Estrutura de pastas

```
bloco-notas-php/
├── banco/
│   ├── schema.sql          tabelas, funções, triggers, views (PostgreSQL)
│   └── semear.php          dados de exemplo
├── config/
│   └── config.php          banco, tamanho mínimo da senha, limite de tentativas
├── public/                 ÚNICA pasta acessível pelo navegador
│   ├── index.php           porta de entrada + TABELA DE ROTAS
│   └── css/estilo.css      cores e aparência (variáveis no topo)
└── src/
    ├── nucleo/             infraestrutura (você raramente mexe)
    │   ├── bootstrap.php   inicia tudo (config, sessão, carrega arquivos)
    │   ├── db.php          conexão PDO e funções consultar/executar/transacao
    │   └── helpers.php     e(), url(), flash, CSRF, login, renderizar()
    ├── modelos/            REGRAS DE NEGÓCIO + SQL  ← onde vive o CRUD
    │   ├── usuarios.php   notas.php   temas.php
    │   └── compartilhamentos.php   historico.php
    ├── controladores/      recebem a requisição, chamam o modelo, escolhem a tela
    │   └── auth.php  notas.php  temas.php  compartilhar.php  admin.php
    └── visoes/             HTML das telas
        └── layout.php (moldura) + auth/ notas/ temas/ admin/
```

**Caminho de uma requisição:** `public/index.php` (rota) → controlador → modelo (SQL) → visão (HTML).

## 5. Rotas (CRUD de notas)

| Operação | Rota | Método | Função no controlador | Função no modelo |
|---|---|---|---|---|
| Listar / buscar | `?r=notas` | GET | `ctrl_notas_listar` | `notas_listar` |
| Abrir | `?r=notas/ver&id=1` | GET | `ctrl_notas_ver` | `nota_obter` |
| Criar (form) | `?r=notas/nova` | GET | `ctrl_notas_nova` | — |
| Criar (gravar) | `?r=notas/criar` | POST | `ctrl_notas_criar` | `nota_criar` |
| Editar (form) | `?r=notas/editar&id=1` | GET | `ctrl_notas_editar` | `nota_obter` |
| Editar (gravar) | `?r=notas/atualizar` | POST | `ctrl_notas_atualizar` | `nota_editar` |
| Excluir (lógico) | `?r=notas/excluir` | POST | `ctrl_notas_excluir` | `nota_excluir` |

Temas, compartilhamento, histórico e administração seguem o mesmo padrão (veja a tabela `$rotas` em `public/index.php`).

## 6. De onde veio cada parte do script MySQL

As *procedures* `sp_*` foram para o PHP (mais fácil de ler e depurar). O banco manteve o que **não pode falhar**.

| Script MySQL | Agora |
|---|---|
| tabelas, UNIQUE, FOREIGN KEY | `banco/schema.sql` (seção 2) |
| `fn_permissao_nota` | `banco/schema.sql` — mesma função, em PostgreSQL |
| triggers do histórico (`trg_notas_ai/au`, imutável) | `banco/schema.sql` (seção 4) |
| views `vw_historico_detalhado`, `vw_temas_resumo` | `banco/schema.sql` (seção 5) |
| `sp_login_falho`, `sp_login_ok` | `usuario_registrar_falha_login()`, `usuario_autenticar()` em `modelos/usuarios.php` |
| `sp_criar_nota`, `sp_editar_nota`, `sp_excluir_nota` | `nota_criar()`, `nota_editar()`, `nota_excluir()` em `modelos/notas.php` |
| `sp_restaurar_versao` | `historico_restaurar()` em `modelos/historico.php` |
| `sp_compartilhar_nota`, `sp_descompartilhar_nota` | `modelos/compartilhamentos.php` |
| `sp_excluir_tema` | `tema_excluir()` em `modelos/temas.php` |
| consultas 10.2 a 10.7 | `notas_listar()`, `nota_obter()`, `historico_listar()` |
| `@usuario_id_atual` | `set_config('app.usuario_id', ...)` dentro de `transacao()` |

### Como o histórico funciona (RN-05)
Toda escrita em `notas` passa por `transacao($uid, ...)` (`src/nucleo/db.php`). Ela diz ao banco **quem** está agindo; os **triggers** gravam o histórico sozinhos. Sem informar o usuário, o banco recusa a alteração. O PHP nunca insere em `historico_alteracoes`.

## 7. Requisitos da ficha → onde estão

| Requisito | Onde |
|---|---|
| RF-01 cadastro / RF-02 login | `controladores/auth.php`, `modelos/usuarios.php` |
| RF-03 CRUD de notas | `modelos/notas.php` |
| RF-04 compartilhar (leitura/edição) | `modelos/compartilhamentos.php` |
| RF-05 histórico / RF-06 restaurar | `modelos/historico.php` + triggers |
| RF-07 abas | *não implementada*: usa as abas do navegador (tabela `abas_abertas` ficou opcional no schema) |
| RF-08 temas | `modelos/temas.php`, filtro em `notas_listar()` |
| RF-09 busca | `notas_listar()` (índice de texto completo + `ILIKE`) |
| RF-10 administração | `controladores/admin.php`, `modelos/usuarios.php` |
| RN-10 bloqueio por tentativas | `usuario_registrar_falha_login()`; números em `config.php` |
| RNF-02 senha com hash | `password_hash()` em `usuario_criar()` |
| RNF-04 acesso negado (403) | `nota_obter()` + `fn_permissao_nota` |

## 8. Receitas de alteração

**Nova página.** (1) escreva `ctrl_<controlador>_<ação>()` em `src/controladores/`; (2) crie a tela em `src/visoes/`; (3) adicione uma linha em `$rotas` (`public/index.php`).

**Novo campo em notas (ex.: cor).**
1. `ALTER TABLE notas ADD COLUMN cor VARCHAR(7) NULL;`
2. `modelos/notas.php`: incluir `cor` nos `SELECT` de `nota_obter()` e no `INSERT`/`UPDATE` de `nota_criar()`/`nota_editar()`.
3. `visoes/notas/form.php`: novo `<input name="cor">`; `controladores/notas.php`: ler com `post_str('cor')` e passar ao modelo.
4. Para versionar no histórico: ver item A do guia no fim de `schema.sql`.

**Novo perfil / nova permissão / nova ação de histórico.** Receitas B, C e D no fim de `schema.sql` (mudam um `CHECK` no banco e uma lista no PHP).

**Limite de tentativas de login / minutos de bloqueio / tamanho mínimo da senha.** Só `config/config.php`.

**Cores do sistema.** Variáveis no início de `public/css/estilo.css`.

**Ordem do histórico.** `ORDER BY ... DESC` em `historico_listar()`.

## 9. Segurança já aplicada

- SQL sempre parametrizado (`:nome`) — sem SQL Injection.
- Toda saída HTML passa por `e()` — sem XSS.
- Todo formulário POST tem token CSRF, validado no roteador.
- Senha com `password_hash` / `password_verify` (bcrypt); sessão renovada após o login.
- Só a pasta `public/` é servida; o código em `src/` e `config/` não é acessível pelo navegador.
- Permissão da nota decidida em um só lugar (`fn_permissao_nota`).

## 10. Problemas comuns

| Sintoma | Causa provável |
|---|---|
| `could not find driver` | extensão `pdo_pgsql` desligada no `php.ini` |
| `password authentication failed` | usuário/senha em `config/config.php` |
| `database "bloco_notas" does not exist` | passo 1 da instalação não foi feito |
| `relation "usuarios" does not exist` | `schema.sql` não foi executado nesse banco |
| `RN-05: defina app.usuario_id...` | algum código alterou `notas` fora de `transacao()` |
| `Call to undefined function mb_strlen()` | extensão `mbstring` desligada no `php.ini` |
| "Página não encontrada" | a rota digitada em `?r=` não existe na tabela `$rotas` |
