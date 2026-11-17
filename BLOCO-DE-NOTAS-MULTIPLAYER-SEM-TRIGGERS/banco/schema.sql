/* =====================================================================
   BLOCO DE NOTAS COMPARTILHADO - SENAI JOINVILLE
   Banco MySQL 5.7+ / 8.0+ / MariaDB 10.x - SOMENTE TABELAS
   ---------------------------------------------------------------------
   Este script NÃO usa triggers, funções armazenadas, procedures, views
   nem DELIMITER. Por isso roda em hospedagem compartilhada (Hostinger,
   InfinityFree...) e pode ser importado em qualquer cliente: phpMyAdmin,
   MySQL Workbench, terminal ou até pelo PDO.

   As regras que antes ficavam em triggers e função agora estão no PHP:
     - histórico automático (RF-05, RN-05) -> src/modelos/historico.php
                                              (historico_registrar)
     - permissão da nota (RN-04, RNF-04)   -> src/modelos/notas.php
                                              (nota_permissao)

   COMO EXECUTAR
   * Hospedagem (Hostinger, InfinityFree...): crie o banco no painel,
     abra o phpMyAdmin DESSE banco, aba "Importar", e envie este arquivo.
   * Local (terminal):
       mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS bloco_notas
                            CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
       mysql -u root -p bloco_notas < banco/schema.sql
     Pode ser executado de novo sem apagar dados (CREATE ... IF NOT EXISTS).

   OBSERVAÇÕES DE COMPATIBILIDADE
   * Cada tabela declara utf8mb4 / utf8mb4_unicode_ci. A collation ignora
     maiúsculas/minúsculas e acentos ("MARIA@x.com" = "maria@x.com").
   * Nenhuma tabela força ENGINE: vale o padrão do servidor (InnoDB nos
     servidores atuais). Com InnoDB, chaves estrangeiras e transações
     funcionam. Num servidor antigo com MyISAM, o script ainda roda, mas
     as chaves estrangeiras são ignoradas e as transações não desfazem nada.

   SEÇÕES
     1. Tabelas (usuarios, temas, notas, notas_temas,
        compartilhamentos, abas_abertas, historico_alteracoes)
     2. Consultas úteis para testar
     3. Guia de adaptações
   ===================================================================== */

/* =====================================================================
   1. TABELAS
   Convenções (mantenha ao adaptar):
     - nomes de tabelas no plural e em minúsculas
     - chave primária sempre "id"
     - chave estrangeira = <tabela_no_singular>_id
     - criado_em / atualizado_em em tabelas que mudam
   Ordem importante: tabelas "pai" antes das tabelas "filhas".
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 1.1 USUARIOS  (RF-01, RF-02, RF-10, RN-01, RN-09, RN-10, RNF-02)
-- A senha NUNCA é guardada em texto puro: o PHP gera o hash com
-- password_hash() (bcrypt) e grava aqui em senha_hash.
-- A regra de senha mínima (RN-09) é validada no PHP (config.php).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome              VARCHAR(100) NOT NULL,
  email             VARCHAR(150) NOT NULL,
  senha_hash        VARCHAR(255) NOT NULL,
  perfil            ENUM('usuario','administrador')
                    NOT NULL DEFAULT 'usuario',      -- ADAPTAR: novos perfis (guia, item B)
  bloqueado         TINYINT(1) NOT NULL DEFAULT 0,   -- bloqueio manual (RF-10)
  tentativas_login  TINYINT UNSIGNED NOT NULL DEFAULT 0,  -- RN-10
  bloqueado_ate     DATETIME NULL,                   -- RN-10 (temporário)
  criado_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                    ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_usuarios_email UNIQUE (email)        -- RN-01: e-mail único
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1.2 TEMAS  (RF-08, RN-08)
-- Cada tema pertence a um usuário; o nome é único POR usuário.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS temas (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  usuario_id  INT UNSIGNED NOT NULL,
  nome        VARCHAR(80)  NOT NULL,
  criado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_temas_usuario_nome UNIQUE (usuario_id, nome),  -- RN-08
  CONSTRAINT fk_temas_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1.3 NOTAS  (RF-03, RN-03, RN-06, RF-09)
-- Exclusão LÓGICA (RN-06): a nota nunca some do banco, só recebe
-- excluida = 1. Assim o histórico continua existindo.
-- MEDIUMTEXT aceita até ~16 MB. ADAPTAR: guia, item F.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  dono_id        INT UNSIGNED NOT NULL,              -- RN-03: quem criou é o dono
  titulo         VARCHAR(200) NOT NULL,
  conteudo       MEDIUMTEXT   NOT NULL,              -- '' = nota vazia
  excluida       TINYINT(1)   NOT NULL DEFAULT 0,    -- RN-06
  excluida_em    DATETIME NULL,
  criado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                 ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notas_dono (dono_id, excluida),            -- acelera "minhas notas"
  CONSTRAINT fk_notas_dono FOREIGN KEY (dono_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1.4 NOTAS_TEMAS  (RF-08, RN-07)
-- Tabela de ligação N:N: uma nota pode ter vários temas e um tema pode
-- ter várias notas. A chave primária composta evita duplicidade.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas_temas (
  nota_id  INT UNSIGNED NOT NULL,
  tema_id  INT UNSIGNED NOT NULL,
  PRIMARY KEY (nota_id, tema_id),
  CONSTRAINT fk_nt_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE CASCADE,
  -- RESTRICT: não deixa apagar um tema que ainda tem notas (RN-07).
  -- Para excluir com confirmação, use tema_excluir() no PHP.
  CONSTRAINT fk_nt_tema FOREIGN KEY (tema_id)
    REFERENCES temas (id) ON DELETE RESTRICT
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1.5 COMPARTILHAMENTOS  (RF-04, RN-03, RN-04)
-- Uma linha = "este usuário tem esta permissão nesta nota".
-- O DONO não precisa de linha aqui (ele já é o dono em notas.dono_id).
-- ADAPTAR: nova permissão (ex.: 'comentario') = guia, item C.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS compartilhamentos (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nota_id     INT UNSIGNED NOT NULL,
  usuario_id  INT UNSIGNED NOT NULL,                 -- quem recebeu o acesso
  permissao   ENUM('leitura','edicao') NOT NULL DEFAULT 'leitura',
  criado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_comp_nota_usuario UNIQUE (nota_id, usuario_id),
  CONSTRAINT fk_comp_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE CASCADE,
  CONSTRAINT fk_comp_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE CASCADE
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1.6 ABAS_ABERTAS  (RF-07)  *** OPCIONAL / SEM TELA NESTA VERSÃO ***
-- A ficha trata as abas como recurso da interface. A aplicação PHP não
-- usa esta tabela (as "abas" são as abas do próprio navegador). Mantida
-- para não perder a modelagem; pode ser removida sem afetar o sistema.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS abas_abertas (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  usuario_id  INT UNSIGNED NOT NULL,
  nota_id     INT UNSIGNED NOT NULL,
  posicao     SMALLINT UNSIGNED NOT NULL DEFAULT 0,  -- ordem da aba
  ativa       TINYINT(1) NOT NULL DEFAULT 0,         -- aba selecionada
  aberta_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_abas_usuario_nota UNIQUE (usuario_id, nota_id),
  CONSTRAINT fk_abas_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE CASCADE,
  CONSTRAINT fk_abas_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE CASCADE
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1.7 HISTORICO_ALTERACOES  (RF-05, RF-06, RN-05)
-- Registra QUEM fez, O QUÊ fez e QUANDO.
-- titulo_anterior / conteudo_anterior guardam a versão ANTES da
-- alteração; é daqui que se consulta e restaura versões antigas.
-- Esta tabela é preenchida SOMENTE por historico_registrar()
-- (src/modelos/historico.php), chamada dentro de uma transação junto
-- com a alteração da nota. Nenhum outro código a altera ou apaga
-- (RN-05: o histórico é imutável).
-- ADAPTAR: retenção de histórico = guia, item H.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS historico_alteracoes (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nota_id           INT UNSIGNED NOT NULL,
  usuario_id        INT UNSIGNED NOT NULL,           -- autor da alteração
  acao              ENUM('criacao','edicao','exclusao','restauracao')
                    NOT NULL,                        -- ADAPTAR: novas ações (guia, item D)
  titulo_anterior   VARCHAR(200) NULL,
  conteudo_anterior MEDIUMTEXT NULL,
  criado_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_hist_nota_data (nota_id, criado_em),
  CONSTRAINT fk_hist_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_hist_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =====================================================================
   2. CONSULTAS ÚTEIS PARA TESTAR (phpMyAdmin, aba SQL)
   (a aplicação PHP usa versões parametrizadas destas consultas)
   ---------------------------------------------------------------------
   -- Notas visíveis para o usuário 3 (próprias + compartilhadas):
   --   SELECT n.id, n.titulo,
   --          CASE WHEN n.dono_id = 3 THEN 'dono' ELSE c.permissao END AS permissao
   --     FROM notas n
   --     LEFT JOIN compartilhamentos c ON c.nota_id = n.id AND c.usuario_id = 3
   --    WHERE n.excluida = 0 AND (n.dono_id = 3 OR c.id IS NOT NULL);
   -- Histórico de uma nota (RF-05):
   --   SELECT h.id, u.nome AS autor, h.acao, h.criado_em
   --     FROM historico_alteracoes h JOIN usuarios u ON u.id = h.usuario_id
   --    WHERE h.nota_id = 1 ORDER BY h.criado_em, h.id;
   ===================================================================== */

/* =====================================================================
   3. GUIA DE ADAPTAÇÕES (receitas prontas)
   ---------------------------------------------------------------------
   A) ADICIONAR UMA COLUNA (ex.: cor da nota)
        ALTER TABLE notas ADD COLUMN cor VARCHAR(7) NULL AFTER conteudo;
      Depois: inclua a coluna nos SELECT/INSERT/UPDATE de
      src/modelos/notas.php e no formulário src/visoes/notas/form.php.
      Para versionar no histórico: adicione "cor_anterior" em
      historico_alteracoes e passe o valor em historico_registrar().

   B) NOVO PERFIL DE USUÁRIO (ex.: 'moderador')
        ALTER TABLE usuarios MODIFY perfil
          ENUM('usuario','moderador','administrador')
          NOT NULL DEFAULT 'usuario';
      Depois: acrescente o perfil em PERFIS e em PERFIS_ROTULOS de
      src/modelos/usuarios.php. A PRIMEIRA conta criada no sistema vira
      'administrador' automaticamente (usuario_criar sem perfil).
      Para promover alguém direto no banco (ex.: perdeu o acesso de admin):
        UPDATE usuarios SET perfil = 'administrador' WHERE email = 'a@b.com';

   C) NOVA PERMISSÃO DE COMPARTILHAMENTO (ex.: 'comentario')
        ALTER TABLE compartilhamentos MODIFY permissao
          ENUM('leitura','comentario','edicao') NOT NULL DEFAULT 'leitura';
      Depois ajuste em src/modelos/: a lista de permissões válidas em
      compartilhar_nota() e quem pode editar em nota_editar().
      nota_permissao() não muda (só devolve o valor).

   D) NOVA AÇÃO NO HISTÓRICO (ex.: 'compartilhamento')
        ALTER TABLE historico_alteracoes MODIFY acao
          ENUM('criacao','edicao','exclusao','restauracao','compartilhamento')
          NOT NULL;
      Depois chame historico_registrar(..., 'compartilhamento') no ponto
      desejado de src/modelos/compartilhamentos.php.

   E) MUDAR O LIMITE DE TENTATIVAS / TEMPO DE BLOQUEIO (RN-10)
      Não mexe no banco: edite login_max_tentativas e
      login_bloqueio_minutos em config/config.php.

   F) LIMITAR TAMANHO DA NOTA
        ALTER TABLE notas MODIFY conteudo TEXT NOT NULL;   -- até 64 KB
        ALTER TABLE historico_alteracoes MODIFY conteudo_anterior TEXT NULL;

   G) TEMAS COMPARTILHADOS POR GRUPO
      Crie "grupos" e "grupos_usuarios", troque temas.usuario_id por
      grupo_id e ajuste UNIQUE (grupo_id, nome) e tema_excluir().

   H) RETENÇÃO DO HISTÓRICO (ex.: manter 2 anos)
        DELETE FROM historico_alteracoes
         WHERE criado_em < NOW() - INTERVAL 2 YEAR;
      (nenhum trigger bloqueia mais o DELETE: faça isso só de propósito,
       com backup, e nunca dentro da aplicação)

   I) BOA PRÁTICA GERAL
      - Antes de qualquer ALTER em produção, faça backup (RNF-06): no
        phpMyAdmin, aba "Exportar"; no terminal,
          mysqldump -u root -p bloco_notas > backup_bloco_notas.sql
      - Nunca grave senha em texto puro (RNF-02).
      - Sempre use consultas parametrizadas no PHP (nunca concatene
        dados do usuário dentro do SQL).
      - Teste mudanças primeiro em um banco de desenvolvimento.
   ===================================================================== */
