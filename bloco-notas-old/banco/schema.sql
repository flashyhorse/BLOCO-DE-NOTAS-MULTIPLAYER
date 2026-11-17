/* =====================================================================
   BLOCO DE NOTAS COMPARTILHADO - SENAI JOINVILLE
   Banco de dados MySQL 8.0+ (InnoDB / utf8mb4)
   ---------------------------------------------------------------------
   COMO LER ESTE SCRIPT
   O arquivo está dividido em seções numeradas. Cada seção diz:
     - O QUE ela cria
     - QUAL requisito (RF / RNF / RN da ficha) ela atende
     - COMO adaptar caso o projeto mude

   COMO EXECUTAR (uma vez só, na pasta do projeto)
     mysql -u root -p < banco/schema.sql
   O script cria o banco "bloco_notas" e tudo o que há dentro dele.
   Pode ser executado de novo sem apagar dados: tabelas e views só são
   criadas se não existirem; função e triggers são recriados.

   IMPORTANTE: este arquivo usa a linha DELIMITER, que só o cliente
   "mysql" (terminal), o MySQL Workbench e o phpMyAdmin entendem.
   Em drivers (PHP, JDBC, Node) NÃO execute o arquivo inteiro de uma vez.

   SEÇÕES
     1. Criação do banco
     2. Tabelas (usuarios, temas, notas, notas_temas,
        compartilhamentos, abas_abertas, historico_alteracoes)
     3. Função de permissão
     4. Triggers (histórico automático, proteção do histórico)
     5. Views
     6. Consultas úteis para testar no cliente mysql
     7. Guia de adaptações

   ONDE FICOU O RESTANTE DO SCRIPT ORIGINAL
     As PROCEDUREs sp_* (login, notas, compartilhamento, temas) viraram
     funções PHP em src/modelos/ (mapa completo no README.md). O banco
     continua garantindo as regras que NÃO podem falhar: unicidade,
     chaves estrangeiras, permissão da nota, histórico automático e
     histórico imutável.
   ===================================================================== */

/* =====================================================================
   1. CRIAÇÃO DO BANCO
   ===================================================================== */
CREATE DATABASE IF NOT EXISTS bloco_notas
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE bloco_notas;

-- Para recomeçar do zero em DESENVOLVIMENTO, descomente a linha abaixo
-- e execute este arquivo de novo (apaga TUDO, nunca use em produção):
-- DROP DATABASE bloco_notas;

/* =====================================================================
   2. TABELAS
   Convenções usadas (mantenha ao adaptar):
     - nomes de tabelas no plural e em minúsculas
     - chave primária sempre "id"
     - chave estrangeira = <tabela_no_singular>_id
     - criado_em / atualizado_em em tabelas que mudam
   Ordem importante: tabelas "pai" antes das tabelas "filhas".
   Observação: a collation utf8mb4_unicode_ci ignora maiúsculas/minúsculas
   e acentos nas comparações ("MARIA@x.com" = "maria@x.com").
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 2.1 USUARIOS  (RF-01, RF-02, RF-10, RN-01, RN-09, RN-10, RNF-02)
-- A senha NUNCA é guardada em texto puro: o PHP gera o hash com
-- password_hash() (bcrypt) e grava aqui em senha_hash.
-- A regra de senha mínima (RN-09) é validada no PHP (config.php).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome              VARCHAR(100) NOT NULL,
  email             VARCHAR(150) NOT NULL,
  senha_hash        VARCHAR(255) NOT NULL,
  perfil            ENUM('aluno','instrutor','administrador')
                    NOT NULL DEFAULT 'aluno',        -- ADAPTAR: novos perfis (guia, item B)
  bloqueado         TINYINT(1) NOT NULL DEFAULT 0,   -- bloqueio manual (RF-10)
  tentativas_login  TINYINT UNSIGNED NOT NULL DEFAULT 0,  -- RN-10
  bloqueado_ate     DATETIME NULL,                   -- RN-10 (temporário)
  criado_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                    ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_usuarios_email UNIQUE (email)        -- RN-01: e-mail único
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2.2 TEMAS  (RF-08, RN-08)
-- Cada tema pertence a um usuário; o nome é único POR usuário.
-- ADAPTAR: para temas compartilhados por grupo, crie a tabela "grupos"
-- e troque usuario_id por grupo_id (e o UNIQUE também).
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
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2.3 NOTAS  (RF-03, RN-03, RN-06, RF-09)
-- Exclusão LÓGICA (RN-06): a nota nunca some do banco, só recebe
-- excluida = 1. Assim o histórico continua existindo.
-- O limite de tamanho está em aberto na ficha ("validar com o
-- cliente"): MEDIUMTEXT aceita até ~16 MB. ADAPTAR: guia, item F.
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
  -- RF-09: índice de texto completo (para MATCH ... AGAINST). A busca da
  -- aplicação (src/modelos/notas.php) usa LIKE, que aceita termos curtos.
  FULLTEXT KEY ft_notas_busca (titulo, conteudo),
  CONSTRAINT fk_notas_dono FOREIGN KEY (dono_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2.4 NOTAS_TEMAS  (RF-08, RN-07)
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
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2.5 COMPARTILHAMENTOS  (RF-04, RN-03, RN-04)
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
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2.6 ABAS_ABERTAS  (RF-07)  *** OPCIONAL / SEM TELA NESTA VERSÃO ***
-- A ficha trata as abas como recurso da interface. Esta tabela só é
-- necessária se o cliente quiser que as abas abertas voltem quando o
-- usuário entrar de novo. A aplicação PHP não a usa (as "abas" são as
-- abas do próprio navegador). Mantida para não perder a modelagem.
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
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2.7 HISTORICO_ALTERACOES  (RF-05, RF-06, RN-05)
-- Registra QUEM fez, O QUÊ fez e QUANDO.
-- titulo_anterior / conteudo_anterior guardam a versão ANTES da
-- alteração; é daqui que se consulta e restaura versões antigas.
-- Esta tabela é preenchida por TRIGGERS (seção 4), nunca pelo PHP
-- diretamente, para garantir a RN-05.
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
) ENGINE=InnoDB;

/* =====================================================================
   3. FUNÇÃO DE PERMISSÃO  (RNF-04, RN-03, RN-04)
   Centraliza a pergunta "o que este usuário pode fazer nesta nota?".
   Retorna: 'dono' | 'edicao' | 'leitura' | NULL (sem acesso -> 403).
   Nota inexistente ou excluída também retorna NULL.
   Todo o PHP usa esta função, então uma regra nova de acesso é
   alterada em UM lugar só.
   ===================================================================== */
DELIMITER $$

DROP FUNCTION IF EXISTS fn_permissao_nota$$
CREATE FUNCTION fn_permissao_nota(p_nota_id INT UNSIGNED, p_usuario_id INT UNSIGNED)
RETURNS VARCHAR(10)
READS SQL DATA
BEGIN
  DECLARE v_permissao VARCHAR(10) DEFAULT NULL;

  -- 1) é o dono (e a nota não foi excluída)?
  SET v_permissao = (
    SELECT 'dono' FROM notas
     WHERE id = p_nota_id AND dono_id = p_usuario_id AND excluida = 0
     LIMIT 1
  );

  -- 2) senão, recebeu compartilhamento?
  IF v_permissao IS NULL THEN
    SET v_permissao = (
      SELECT c.permissao
        FROM compartilhamentos c
        JOIN notas n ON n.id = c.nota_id
       WHERE c.nota_id = p_nota_id
         AND c.usuario_id = p_usuario_id
         AND n.excluida = 0
       LIMIT 1
    );
  END IF;

  RETURN v_permissao;
END$$

/* =====================================================================
   4. TRIGGERS  (RF-05, RN-05)
   Triggers são "gatilhos": o próprio banco executa o código quando uma
   linha é inserida/alterada. Assim o histórico é gravado SEMPRE, mesmo
   que alguém esqueça de chamá-lo no PHP.

   COMO O BANCO SABE QUEM ALTEROU?
   O PHP abre uma transação e executa, na mesma conexão, ANTES de mexer
   em notas:
       SET @usuario_id_atual = <id do usuário logado>;
   (a função transacao() em src/nucleo/db.php já faz isso por você e
   zera a variável no fim.) Sem ela, a alteração é recusada (RN-05).
   ===================================================================== */

-- 4.1 Nova nota -> registra 'criacao'
DROP TRIGGER IF EXISTS trg_notas_ai$$
CREATE TRIGGER trg_notas_ai AFTER INSERT ON notas
FOR EACH ROW
BEGIN
  IF @usuario_id_atual IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-05: defina @usuario_id_atual antes de criar a nota';
  END IF;

  INSERT INTO historico_alteracoes (nota_id, usuario_id, acao)
  VALUES (NEW.id, @usuario_id_atual, 'criacao');
END$$

-- 4.2 Nota alterada -> registra 'edicao', 'exclusao' ou 'restauracao'
DROP TRIGGER IF EXISTS trg_notas_au$$
CREATE TRIGGER trg_notas_au AFTER UPDATE ON notas
FOR EACH ROW
BEGIN
  DECLARE v_acao VARCHAR(15) DEFAULT NULL;

  IF OLD.excluida = 0 AND NEW.excluida = 1 THEN
    SET v_acao = 'exclusao';
  ELSEIF CAST(OLD.titulo   AS BINARY) <> CAST(NEW.titulo   AS BINARY)
      OR CAST(OLD.conteudo AS BINARY) <> CAST(NEW.conteudo AS BINARY) THEN
    -- A comparação é BINÁRIA de propósito: com a collation unicode_ci,
    -- trocar "aula" por "AULA" ou "acao" por "ação" seria considerado
    -- "igual" e a edição ficaria sem histórico.
    -- @acao_historico = 'restauracao' é definido pelo PHP em
    -- historico_restaurar(); nos demais casos é uma edição comum.
    SET v_acao = COALESCE(NULLIF(@acao_historico, ''), 'edicao');
  END IF;

  -- Se nada relevante mudou (ex.: só atualizado_em), não registra nada.
  IF v_acao IS NOT NULL THEN
    IF @usuario_id_atual IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RN-05: defina @usuario_id_atual antes de alterar a nota';
    END IF;

    INSERT INTO historico_alteracoes
      (nota_id, usuario_id, acao, titulo_anterior, conteudo_anterior)
    VALUES
      (OLD.id, @usuario_id_atual, v_acao, OLD.titulo, OLD.conteudo);
  END IF;
END$$

-- 4.3 Histórico é imutável (RN-05): proíbe UPDATE e DELETE
DROP TRIGGER IF EXISTS trg_historico_bu$$
CREATE TRIGGER trg_historico_bu BEFORE UPDATE ON historico_alteracoes
FOR EACH ROW
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'RN-05: registros de historico nao podem ser editados'$$

DROP TRIGGER IF EXISTS trg_historico_bd$$
CREATE TRIGGER trg_historico_bd BEFORE DELETE ON historico_alteracoes
FOR EACH ROW
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'RN-05: registros de historico nao podem ser apagados'$$
-- ADAPTAR: se um dia for preciso limpar o histórico (retenção), veja
-- o guia, item H.

DELIMITER ;

/* =====================================================================
   5. VIEWS  (consultas reutilizáveis)
   View = "consulta salva" com nome. Útil para o PHP não repetir JOINs.
   ADAPTAR: se adicionar colunas nas tabelas, inclua-as aqui.
   ===================================================================== */

-- 5.1 Histórico legível: mostra o NOME do autor e o título da nota (RF-05)
CREATE OR REPLACE VIEW vw_historico_detalhado AS
  SELECT h.id           AS historico_id,
         h.nota_id,
         n.titulo       AS titulo_atual_da_nota,
         u.nome         AS autor,
         h.acao,
         h.titulo_anterior,
         h.conteudo_anterior,
         h.criado_em    AS data_hora
    FROM historico_alteracoes h
    JOIN usuarios u ON u.id = h.usuario_id
    JOIN notas    n ON n.id = h.nota_id;

-- 5.2 Temas com a quantidade de notas ativas (alimenta a lista de temas)
CREATE OR REPLACE VIEW vw_temas_resumo AS
  SELECT t.id          AS tema_id,
         t.usuario_id,
         t.nome        AS tema,
         COUNT(n.id)   AS total_notas
    FROM temas t
    LEFT JOIN notas_temas nt ON nt.tema_id = t.id
    LEFT JOIN notas n        ON n.id = nt.nota_id AND n.excluida = 0
   GROUP BY t.id, t.usuario_id, t.nome;

/* =====================================================================
   6. CONSULTAS ÚTEIS PARA TESTAR NO CLIENTE mysql
   (a aplicação PHP usa versões parametrizadas destas consultas)
   ---------------------------------------------------------------------
   -- Quem sou eu? (troque 3 pelo id do usuário)
   --   SET @uid = 3;
   -- Minhas notas (próprias + compartilhadas) com a permissão:
   --   SELECT id, titulo, fn_permissao_nota(id, @uid) AS permissao
   --     FROM notas
   --    WHERE excluida = 0 AND fn_permissao_nota(id, @uid) IS NOT NULL;
   -- Busca (RF-09):
   --   SELECT id, titulo FROM notas
   --    WHERE excluida = 0 AND fn_permissao_nota(id, @uid) IS NOT NULL
   --      AND (titulo LIKE '%modelagem%' OR conteudo LIKE '%modelagem%');
   -- Busca por relevância com o índice FULLTEXT (só palavras com 3+ letras):
   --   SELECT id, titulo, MATCH(titulo, conteudo) AGAINST ('modelagem') AS relevancia
   --     FROM notas
   --    WHERE MATCH(titulo, conteudo) AGAINST ('modelagem')
   --    ORDER BY relevancia DESC;
   -- Histórico de uma nota (RF-05):
   --   SELECT * FROM vw_historico_detalhado WHERE nota_id = 1
   --    ORDER BY data_hora, historico_id;
   -- Testar a RN-05 (deve dar ERRO, pois não há usuário informado):
   --   SET @usuario_id_atual = NULL;
   --   UPDATE notas SET titulo = 'x' WHERE id = 1;
   ===================================================================== */

/* =====================================================================
   7. GUIA DE ADAPTAÇÕES (receitas prontas)
   ---------------------------------------------------------------------
   A) ADICIONAR UMA COLUNA (ex.: cor da nota)
        ALTER TABLE notas ADD COLUMN cor VARCHAR(7) NULL AFTER conteudo;
      Depois: inclua a coluna nos SELECT/INSERT/UPDATE de
      src/modelos/notas.php e no formulário src/visoes/notas/form.php.
      Se a coluna deve ser versionada no histórico, adicione também
      "cor_anterior" em historico_alteracoes e inclua-a no trigger
      trg_notas_au (no INSERT e na comparação de mudança).

   B) NOVO PERFIL DE USUÁRIO (ex.: 'coordenador')
        ALTER TABLE usuarios MODIFY perfil
          ENUM('aluno','instrutor','coordenador','administrador')
          NOT NULL DEFAULT 'aluno';
      Depois: acrescente o perfil na constante PERFIS de
      src/modelos/usuarios.php.

   C) NOVA PERMISSÃO DE COMPARTILHAMENTO (ex.: 'comentario')
        ALTER TABLE compartilhamentos MODIFY permissao
          ENUM('leitura','comentario','edicao') NOT NULL DEFAULT 'leitura';
      Depois ajuste em src/modelos/: a lista de permissões válidas em
      compartilhar_nota() e quem pode editar em nota_editar().
      fn_permissao_nota não muda (só devolve o valor).

   D) NOVA AÇÃO NO HISTÓRICO (ex.: 'compartilhamento')
        ALTER TABLE historico_alteracoes MODIFY acao
          ENUM('criacao','edicao','exclusao','restauracao','compartilhamento')
          NOT NULL;
      Crie um trigger AFTER INSERT em compartilhamentos que grave a ação.

   E) MUDAR O LIMITE DE TENTATIVAS / TEMPO DE BLOQUEIO (RN-10)
      Não mexe no banco: edite login_max_tentativas e
      login_bloqueio_minutos em config/config.php.

   F) LIMITAR TAMANHO DA NOTA
        ALTER TABLE notas MODIFY conteudo TEXT NOT NULL;   -- até 64 KB
      (o histórico também guarda conteudo_anterior: ajuste igual)
        ALTER TABLE historico_alteracoes MODIFY conteudo_anterior TEXT NULL;

   G) TEMAS COMPARTILHADOS POR GRUPO
      Crie "grupos" e "grupos_usuarios", troque temas.usuario_id por
      grupo_id e ajuste UNIQUE (grupo_id, nome) e tema_excluir().

   H) RETENÇÃO DO HISTÓRICO (ex.: manter 2 anos)
        -- 1) DROP TRIGGER trg_historico_bd;
        -- 2) DELETE FROM historico_alteracoes
        --     WHERE criado_em < NOW() - INTERVAL 2 YEAR;
        -- 3) recrie trg_historico_bd (seção 4.3)

   I) BOA PRÁTICA GERAL
      - Antes de qualquer ALTER em produção, faça backup (RNF-06):
          mysqldump -u root -p bloco_notas > backup_bloco_notas.sql
      - Nunca grave senha em texto puro (RNF-02).
      - Sempre use consultas parametrizadas no PHP (nunca concatene
        dados do usuário dentro do SQL).
      - Teste mudanças primeiro em um banco de desenvolvimento.
   ===================================================================== */
