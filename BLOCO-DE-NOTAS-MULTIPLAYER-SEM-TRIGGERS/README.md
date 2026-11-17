# Bloco de Notas Compartilhado — PHP + MySQL

CRUD web do projeto **Senai Joinville**, escrito em PHP puro (sem framework) sobre MySQL.
O banco usa **somente tabelas** (sem triggers, funções nem views), então roda também em hospedagem compartilhada (Hostinger, InfinityFree...). Veja a seção 11.
O código foi organizado para ser **lido de cima para baixo** e **alterado em poucos lugares**:
cada arquivo começa com um comentário dizendo o que faz, qual requisito (RF/RN) atende e como adaptar.

## 1. Requisitos

| Item | Versão |
|---|---|
| PHP | 8.0 ou superior, com as extensões **pdo_mysql** e **mbstring** |
| MySQL | 5.7 ou superior / MySQL 8 (MariaDB 10.x também deve funcionar) |

Verificar: `php -m | grep -E "pdo_mysql|mbstring"` (Windows: `php -m | findstr /i "mysql mbstring"`).
Se faltar alguma, abra o `php.ini` e remova o `;` das linhas `extension=pdo_mysql` e `extension=mbstring`.

## 2. Instalação local (uma vez)

```bash
# 1) criar o banco vazio e depois as tabelas
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS bloco_notas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root -p bloco_notas < banco/schema.sql

# 2) ajustar usuário/senha do banco em config/config.php
#    (ou use as variáveis de ambiente DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS)

# 3) (opcional) dados de exemplo — senha de todos: senha1234
php banco/semear.php
```

O `schema.sql` não usa `DELIMITER`, então também pode ser importado pelo phpMyAdmin
(*Importar*, com o banco já selecionado), pelo MySQL Workbench (*File → Run SQL Script*) ou por qualquer driver.

## 3. Executar

```bash
php -S localhost:8000 -t public
```

Abra <http://localhost:8000>. Logins de exemplo (se rodou o `semear.php`): `admin@senai.exemplo`, `maria@senai.exemplo`, `joao@senai.exemplo`.

Sem dados de exemplo? Abra `?r=registrar` e crie a primeira conta: ela vira **administradora** automaticamente (veja a seção 12).

## 4. Estrutura de pastas

```
bloco-notas-php/
├── banco/
│   ├── schema.sql          SÓ tabelas (MySQL) - sem triggers, funções ou views
│   ├── migracao_remover_cargos.sql   só para bancos antigos (aluno/instrutor -> usuario)
│   └── semear.php          dados de exemplo (só desenvolvimento)
├── config/
│   ├── config.php          banco, tamanho mínimo da senha, limite de tentativas
│   └── config.local.exemplo.php   modelo do config.local.php de produção
├── public/                 ÚNICA pasta acessível pelo navegador
│   ├── index.php           porta de entrada + TABELA DE ROTAS
│   └── css/estilo.css      cores e aparência (variáveis no topo)
└── src/
    ├── nucleo/             infraestrutura (você raramente mexe)
    │   ├── bootstrap.php   inicia tudo (config, sessão, carrega arquivos)
    │   ├── db.php          conexão PDO e funções consultar/executar/ultimo_id/transacao
    │   └── helpers.php     e(), url(), flash, CSRF, login, renderizar()
    ├── modelos/            REGRAS DE NEGÓCIO + SQL  ← onde vive o CRUD
    │   ├── usuarios.php   notas.php   temas.php
    │   └── compartilhamentos.php   historico.php
    ├── controladores/      recebem a requisição, chamam o modelo, escolhem a tela
    │   └── auth.php  notas.php  temas.php  compartilhar.php  admin.php
    └── visoes/             HTML das telas
        └── layout.php (moldura) + auth/ notas/ temas/ admin/
```

Cada uma das pastas `banco/`, `config/` e `src/` tem um `.htaccess` que bloqueia o acesso pelo navegador (Apache/LiteSpeed).

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

O script MySQL original tinha *procedures* `sp_*`, uma função, triggers e views. Nada disso existe mais no banco:
hospedagens compartilhadas costumam proibir esses recursos, e o PHP é mais fácil de ler e depurar.
O banco manteve só o que **não pode falhar**: unicidade (`UNIQUE`) e chaves estrangeiras.

| Script MySQL | Agora |
|---|---|
| tabelas, UNIQUE, FOREIGN KEY | `banco/schema.sql` |
| `fn_permissao_nota` | `sql_permissao()` e `nota_permissao()` em `modelos/notas.php` |
| triggers do histórico (`trg_notas_ai/au`) | `historico_registrar()` em `modelos/historico.php`, chamada por `nota_criar/editar/excluir` e `historico_restaurar` |
| trigger de histórico imutável | só existe `INSERT` em `historico_alteracoes`; nenhum código faz `UPDATE`/`DELETE` nela |
| views `vw_historico_detalhado`, `vw_temas_resumo` | `JOIN`s em `historico_listar()` e `temas_do_usuario()`/`tema_excluir()` |
| `sp_login_falho`, `sp_login_ok` | `usuario_registrar_falha_login()`, `usuario_autenticar()` em `modelos/usuarios.php` |
| `sp_criar_nota`, `sp_editar_nota`, `sp_excluir_nota` | `nota_criar()`, `nota_editar()`, `nota_excluir()` em `modelos/notas.php` |
| `sp_restaurar_versao` | `historico_restaurar()` em `modelos/historico.php` |
| `sp_compartilhar_nota`, `sp_descompartilhar_nota` | `modelos/compartilhamentos.php` |
| `sp_excluir_tema` | `tema_excluir()` em `modelos/temas.php` |
| consultas 10.2 a 10.7 | `notas_listar()`, `nota_obter()`, `historico_listar()` |
| `@usuario_id_atual` | parâmetro `$uid` das funções do modelo |

### Como o histórico funciona (RN-05)
Toda escrita em `notas` roda dentro de `transacao(...)` (`src/nucleo/db.php`). Antes de alterar a nota, a função chama
`historico_registrar()`, que grava a versão **anterior** em `historico_alteracoes`. Se qualquer passo falhar, a transação é
desfeita (nota e histórico nunca divergem). `historico_registrar()` é o único código que escreve nessa tabela, e só faz `INSERT`.

**Atenção:** como não há trigger, a garantia depende do código PHP. Ao criar uma nova forma de alterar notas, chame
`historico_registrar()` na mesma transação. Alterar a tabela `notas` direto no phpMyAdmin não gera histórico.

## 7. Requisitos da ficha → onde estão

| Requisito | Onde |
|---|---|
| RF-01 cadastro / RF-02 login | `controladores/auth.php`, `modelos/usuarios.php` |
| RF-03 CRUD de notas | `modelos/notas.php` |
| RF-04 compartilhar (leitura/edição) | `modelos/compartilhamentos.php` |
| RF-05 histórico / RF-06 restaurar | `modelos/historico.php` (+ chamadas em `modelos/notas.php`) |
| RF-07 abas | *não implementada*: usa as abas do navegador (tabela `abas_abertas` ficou opcional no schema) |
| RF-08 temas | `modelos/temas.php`, filtro em `notas_listar()` |
| RF-09 busca | `notas_listar()` (`LIKE`, sem diferenciar maiúsculas/acentos) |
| RF-10 administração | `controladores/admin.php`, `modelos/usuarios.php` |
| RN-10 bloqueio por tentativas | `usuario_registrar_falha_login()`; números em `config.php` |
| RNF-02 senha com hash | `password_hash()` em `usuario_criar()` |
| RNF-04 acesso negado (403) | `nota_obter()` + `sql_permissao()` |

## 8. Receitas de alteração

**Nova página.** (1) escreva `ctrl_<controlador>_<ação>()` em `src/controladores/`; (2) crie a tela em `src/visoes/`; (3) adicione uma linha em `$rotas` (`public/index.php`).

**Novo campo em notas (ex.: cor).**
1. `ALTER TABLE notas ADD COLUMN cor VARCHAR(7) NULL;`
2. `modelos/notas.php`: incluir `cor` nos `SELECT` de `nota_obter()` e no `INSERT`/`UPDATE` de `nota_criar()`/`nota_editar()`.
3. `visoes/notas/form.php`: novo `<input name="cor">`; `controladores/notas.php`: ler com `post_str('cor')` e passar ao modelo.
4. Para versionar no histórico: ver item A do guia no fim de `schema.sql`.

**Novo perfil / nova permissão / nova ação de histórico.** Receitas B, C e D no fim de `schema.sql` (mudam um `ENUM` no banco e uma lista no PHP). Os perfis atuais são só `usuario` e `administrador` (`PERFIS` em `modelos/usuarios.php`).

**Limite de tentativas de login / minutos de bloqueio / tamanho mínimo da senha.** Só `config/config.php`.

**Cores do sistema.** Variáveis no início de `public/css/estilo.css`.

**Ordem do histórico.** `ORDER BY ... DESC` em `historico_listar()`.

## 9. Segurança já aplicada

- SQL sempre parametrizado (`:nome`) — sem SQL Injection.
- Toda saída HTML passa por `e()` — sem XSS.
- Todo formulário POST tem token CSRF, validado no roteador.
- Senha com `password_hash` / `password_verify` (bcrypt); sessão renovada após o login.
- Só a pasta `public/` deve ser servida; `src/`, `config/` e `banco/` têm `.htaccess` que nega o acesso pelo navegador.
- Cookie de sessão `HttpOnly`, `SameSite=Lax` e `Secure` quando o site está em HTTPS.
- Permissão da nota decidida em um só lugar (`sql_permissao()` em `modelos/notas.php`).

## 10. Problemas comuns

| Sintoma | Causa provável |
|---|---|
| `could not find driver` | extensão `pdo_mysql` desligada no `php.ini` |
| `Access denied for user` (1045) | usuário/senha em `config/config.php` |
| `Connection refused` | MySQL desligado, ou host/porta errados em `config.php` |
| `Unknown database 'bloco_notas'` (1049) | `schema.sql` ainda não foi executado |
| `Table 'bloco_notas.usuarios' doesn't exist` (1146) | `schema.sql` foi executado em outro banco ou falhou no meio |
| Erro 1146 ao abrir o site na hospedagem | importou o `schema.sql` em outro banco, ou o nome do banco no `config.local.php` está sem o prefixo da hospedagem |
| Tela em branco na hospedagem | `debug` está `false`; ligue por alguns minutos no `config.local.php` para ver o erro |
| "Instalação incompleta: pasta src não encontrada" | pastas `src/`, `config/`, `banco/` fora dos lugares que o `public/index.php` procura (seção 11) |
| `Call to undefined function mb_strlen()` | extensão `mbstring` desligada no `php.ini` |
| "Página não encontrada" | a rota digitada em `?r=` não existe na tabela `$rotas` |
| Acentos aparecem como `Ã§` ou `?` | banco/tabelas fora de `utf8mb4`; recrie com o `schema.sql` |

## 11. Publicar em hospedagem (Hostinger, InfinityFree e similares)

Esta versão **não precisa** de triggers, funções, views, `SUPER` nem `DELIMITER`, então não há o que dar errado nessa parte.

### 11.1 Banco de dados
1. No painel da hospedagem, crie o banco e o usuário e anote os 4 dados: **host, nome, usuário, senha**
   (nome e usuário costumam ganhar um prefixo, ex.: `u123456789_bloco` na Hostinger, `if0_12345678_bloco` no InfinityFree;
   o host pode não ser `localhost`, principalmente no InfinityFree: copie do painel).
2. Abra o **phpMyAdmin desse banco** → aba **Importar** → envie `banco/schema.sql`.
   Não precisa editar o arquivo (ele não tem `CREATE DATABASE` nem `USE`).
3. Confira se as 7 tabelas apareceram.

### 11.2 Arquivos
Só o conteúdo de `public/` pode ficar visível na web. Escolha **um** destes layouts; o `public/index.php` encontra o código sozinho nos três:

| Layout | Onde colocar | Quando usar |
|---|---|---|
| A (mais seguro) | conteúdo de `public/` em `public_html/`; pasta `app/` (com `banco/`, `config/`, `src/`) **ao lado** de `public_html/` | se o gerenciador de arquivos deixa criar pastas fora de `public_html` (comum na Hostinger) |
| B | conteúdo de `public/` em `public_html/` (ou `htdocs/`); pasta `app/` **dentro** dela | InfinityFree (só existe `htdocs/`) e qualquer hospedagem que não permita o layout A. Os `.htaccess` de `banco/`, `config/` e `src/` já bloqueiam o acesso |
| C | projeto inteiro como está, apontando o domínio para `public/` | VPS ou hospedagem que permita escolher a pasta raiz |

Resultado do layout B, por exemplo: `htdocs/index.php`, `htdocs/css/`, `htdocs/app/src/`, `htdocs/app/config/`, `htdocs/app/banco/`.
Envie também os arquivos que começam com ponto (`.htaccess`).

### 11.3 Configuração
1. Em `config/`, copie `config.local.exemplo.php` para `config.local.php` e preencha host, nome, usuário e senha do passo 11.1.
2. Deixe `'debug' => false`.
3. No painel, selecione **PHP 8.0 ou superior** e confirme `pdo_mysql` e `mbstring` ativos.
4. Ative o **SSL/HTTPS** gratuito do painel.

### 11.4 Primeiro acesso
- **Não use `semear.php`** em produção (as senhas de exemplo são públicas, e hospedagens gratuitas nem têm terminal).
- Abra `?r=registrar` e crie sua conta **logo depois de publicar**: como é a primeira, ela vira administradora automaticamente (seção 12).

### 11.5 Cuidados
- Faça backup do banco com frequência (phpMyAdmin → *Exportar*).
- Hospedagem gratuita costuma ter limites de acessos, de tamanho e de tempo de execução; para uso real, prefira um plano pago.
- Se o servidor ainda usar tabelas MyISAM (raro hoje), o sistema funciona, mas sem chaves estrangeiras nem *rollback* de transações.

## 12. Contas: usuário comum e administrador

Não há cargos (aluno, professor etc.). Existem só dois tipos de conta:

| Tipo | O que faz |
|---|---|
| **Usuário** | cria, edita e compartilha notas e temas |
| **Administrador** | tudo isso + tela **Administração** (bloquear/desbloquear contas e mudar o tipo de conta) |

**Como nasce o primeiro administrador.** A **primeira conta cadastrada** no sistema (tela `?r=registrar`) vira administradora
sozinha, e a própria tela avisa isso. Não precisa mexer no banco.
Em hospedagem, cadastre-se **logo depois de publicar**: até existir a primeira conta, quem abrir a tela de cadastro primeiro vira administrador.

**Criar outros administradores.** Entre como administrador → **Administração** → mude a coluna *Tipo de conta* da pessoa para
*Administrador* e clique em *Salvar*. O sistema impede que você remova o próprio acesso de administrador ou bloqueie a própria conta.

**Perdeu o acesso de administrador?** No phpMyAdmin (aba SQL):
`UPDATE usuarios SET perfil = 'administrador' WHERE email = 'seu@email.com';`

**Banco criado antes desta mudança** (com os perfis aluno/instrutor)? Execute uma vez `banco/migracao_remover_cargos.sql`.
Ele converte todos em *Usuário* sem apagar contas. Leia o aviso no fim do arquivo: se nenhuma conta sua era administradora, promova a sua.
