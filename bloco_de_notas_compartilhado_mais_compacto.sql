/* =====================================================================
   BLOCO DE NOTAS COMPARTILHADO - SENAI JOINVILLE
   Banco de dados MySQL 8.0+ (InnoDB / utf8mb4)
   ---------------------------------------------------------------------
   COMO LER ESTE SCRIPT
   O arquivo está dividido em seções numeradas. Cada seção diz:
     - O QUE ela cria
     - QUAL requisito (RF / RNF / RN da ficha) ela atende
     - COMO adaptar caso o projeto mude
   Ordem de execução: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 (-> 9 -> 10)
SEÇÕES
     1. Criação do banco
     2. Tabelas (usuários, temas, notas, notas_temas,
        compartilhamentos, abas, histórico)
     3. Função de permissão
     4. Triggers (histórico automático e proteção do histórico)
     5. Procedures de login (bloqueio por tentativas)
     6. Procedures de notas (criar, editar, excluir, restaurar)
     7. Procedures de compartilhamento e temas
     8. Views
     9. Dados de exemplo (apenas desenvolvimento)
    10. Consultas prontas para o back-end
    11. Guia de adaptações
OBSERVAÇÃO: os comandos DELIMITER funcionam no cliente "mysql" e no
   MySQL Workbench. Em drivers (JDBC, mysql2 do Node) execute cada
   CREATE PROCEDURE / FUNCTION / TRIGGER como um comando separado, sem a linha DELIMITER. ===================================================================== */ /* ===================================================================== 1. CRIAÇÃO DO BANCO ===================================================================== */ CREATE DATABASE IF NOT EXISTS bloco_notas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; USE bloco_notas; -- Para recomeçar do zero em DESENVOLVIMENTO, descomente a linha abaixo -- (apaga TUDO, nunca use em produção):
-- DROP DATABASE bloco_notas;
/* =====================================================================
   2. TABELAS
   Convenções usadas (mantenha ao adaptar):
     - nomes de tabelas no plural e em minúsculas
     - chave primária sempre "id"
     - chave estrangeira = <tabela_no_singular>_id
     - criado_em / atualizado_em em tabelas que mudam
   Ordem importante: tabelas "pai" antes das tabelas "filhas".
   ===================================================================== */
-- ---------------------------------------------------------------------
-- 2.1 USUARIOS  (RF-01, RF-02, RF-10, RN-01, RN-09, RN-10, RNF-02)
-- A senha NUNCA é guardada em texto puro: o back-end gera o hash
-- (bcrypt) e grava aqui em senha_hash.
-- A regra de senha mínima (RN-09) é validada no back-end, pois o
-- banco só enxerga o hash.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT, nome              VARCHAR(100) NOT NULL,
  email             VARCHAR(150) NOT NULL, senha_hash        VARCHAR(255) NOT NULL,
  perfil            ENUM('aluno','instrutor','administrador')
                    NOT NULL DEFAULT 'aluno',   -- ADAPTAR: novos perfis entram aqui
  bloqueado         TINYINT(1) NOT NULL DEFAULT 0,  -- bloqueio manual (RF-10)
  tentativas_login  TINYINT UNSIGNED NOT NULL DEFAULT 0,  -- RN-10
  bloqueado_ate     DATETIME NULL,                        -- RN-10 (temporário)
  criado_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_usuarios_email UNIQUE (email)   -- RN-01: e-mail único
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 2.2 TEMAS  (RF-08, RN-08)
-- Cada tema pertence a um usuário; o nome é único POR usuário.
-- ADAPTAR: para temas compartilhados por grupo, crie a tabela "grupos"
-- e troque usuario_id por grupo_id (e o UNIQUE também).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS temas (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT, usuario_id  INT UNSIGNED NOT NULL,
  nome        VARCHAR(80)  NOT NULL, criado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_temas_usuario_nome UNIQUE (usuario_id, nome),  -- RN-08
  CONSTRAINT fk_temas_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 2.3 NOTAS  (RF-03, RN-03, RN-06, RF-09)
-- Exclusão LÓGICA (RN-06): a nota nunca some do banco, só recebe
-- excluida = 1. Assim o histórico continua existindo.
-- O limite de tamanho da nota está em aberto na ficha ("validar com o
-- cliente"): MEDIUMTEXT aceita até ~16 MB. ADAPTAR: troque por TEXT
-- (64 KB) ou VARCHAR(n) se o cliente definir um limite.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  dono_id        INT UNSIGNED NOT NULL,          -- RN-03: quem criou é o dono
  titulo         VARCHAR(200) NOT NULL,
  conteudo       MEDIUMTEXT   NOT NULL,          -- envie '' para nota vazia
  excluida       TINYINT(1)   NOT NULL DEFAULT 0, -- RN-06
  excluida_em    DATETIME NULL, criado_em      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notas_dono (dono_id, excluida),        -- acelera "minhas notas"
  FULLTEXT KEY ft_notas_busca (titulo, conteudo),-- RF-09: busca por texto
  CONSTRAINT fk_notas_dono FOREIGN KEY (dono_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 2.4 NOTAS_TEMAS  (RF-08, RN-07)
-- Tabela de ligação N:N: uma nota pode ter vários temas e um tema pode
-- ter várias notas. A chave primária composta evita duplicidade.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas_temas (
  nota_id  INT UNSIGNED NOT NULL, tema_id  INT UNSIGNED NOT NULL,
  PRIMARY KEY (nota_id, tema_id),
  CONSTRAINT fk_nt_nota FOREIGN KEY (nota_id)
  REFERENCES notas (id) ON DELETE CASCADE,
  -- RESTRICT: não deixa apagar um tema que ainda tem notas (RN-07).
  -- Para excluir com confirmação, use sp_excluir_tema (seção 7).
  CONSTRAINT fk_nt_tema FOREIGN KEY (tema_id)
    REFERENCES temas (id) ON DELETE RESTRICT
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 2.5 COMPARTILHAMENTOS  (RF-04, RN-03, RN-04)
-- Uma linha = "este usuário tem esta permissão nesta nota".
-- O DONO não precisa de linha aqui (ele já é o dono em notas.dono_id).
-- ADAPTAR: nova permissão (ex.: 'comentario') = acrescente no ENUM e
-- trate o novo valor na função fn_permissao_nota e nas procedures.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS compartilhamentos (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT, nota_id     INT UNSIGNED NOT NULL,
  usuario_id  INT UNSIGNED NOT NULL,     -- quem recebeu o acesso
  permissao   ENUM('leitura','edicao') NOT NULL DEFAULT 'leitura', criado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT uq_comp_nota_usuario UNIQUE (nota_id, usuario_id),
  CONSTRAINT fk_comp_nota FOREIGN KEY (nota_id)
  REFERENCES notas (id) ON DELETE CASCADE,
  CONSTRAINT fk_comp_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE CASCADE
) ENGINE=InnoDB;
-- ---------------------------------------------------------------------
-- 2.6 ABAS_ABERTAS  (RF-07)  *** OPCIONAL ***
-- A ficha trata as abas como recurso da interface (React). Esta tabela
-- só é necessária se o cliente quiser que as abas abertas voltem
-- quando o usuário entrar de novo. Se não quiser, pode ignorar.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS abas_abertas (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT, usuario_id  INT UNSIGNED NOT NULL,
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
-- Esta tabela é preenchida por TRIGGERS (seção 4), nunca pelo
-- back-end diretamente, para garantir a RN-05.
-- ADAPTAR: se o cliente definir tempo de retenção do histórico,
-- crie um EVENT agendado que apague linhas antigas.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS historico_alteracoes (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, nota_id           INT UNSIGNED NOT NULL,
  usuario_id        INT UNSIGNED NOT NULL,       -- autor da alteração
  acao              ENUM('criacao','edicao','exclusao','restauracao')
                    NOT NULL,                    -- ADAPTAR: novas ações aqui
  titulo_anterior   VARCHAR(200) NULL, conteudo_anterior MEDIUMTEXT NULL,
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
   Todas as procedures usam esta função, então uma regra nova de
   acesso é alterada em UM lugar só.
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
   Triggers são "gatilhos": o próprio banco executa o código quando
   uma linha é inserida/alterada. Assim o histórico é gravado SEMPRE,
   mesmo que alguém esqueça de chamá-lo no back-end.
COMO O BANCO SABE QUEM ALTEROU?
   O back-end deve executar, na mesma conexão, ANTES de mexer em notas:
       SET @usuario_id_atual = <id do usuário logado>;
   (As procedures da seção 6 já fazem isso por você.)
   Sem essa variável, a alteração é recusada (garante a RN-05).
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
  ELSEIF OLD.titulo <> NEW.titulo OR OLD.conteudo <> NEW.conteudo THEN
    -- @acao_historico = 'restauracao' é definido por sp_restaurar_versao;
    -- nos demais casos é uma edição comum.
    SET v_acao = COALESCE(@acao_historico, 'edicao');
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
-- ADAPTAR: se um dia for preciso limpar o histórico (retenção), faça
-- DROP TRIGGER trg_historico_bd; execute a limpeza; e recrie o trigger.
/* =====================================================================
   5. PROCEDURES DE LOGIN  (RF-02, RN-10)
   O back-end confere a senha com bcrypt; o banco cuida do contador
   de tentativas e do bloqueio temporário.
Fluxo sugerido no back-end:
     a) buscar usuário (consulta 10.1) - se não vier, credenciais inválidas
     b) comparar a senha com bcrypt
     c) senha errada  -> CALL sp_login_falho(email)
        senha correta -> CALL sp_login_ok(id)
   ===================================================================== */
-- 5.1 Login falhou: soma tentativa e, na 5ª, bloqueia por 15 minutos
DROP PROCEDURE IF EXISTS sp_login_falho$$
CREATE PROCEDURE sp_login_falho(IN p_email VARCHAR(150)) BEGIN -- ATENÇÃO: no UPDATE do MySQL as colunas são atribuídas da esquerda -- para a direita. Por isso bloqueado_ate vem ANTES de tentativas_login -- (assim ele ainda enxerga o valor antigo do contador).
  UPDATE usuarios
  SET bloqueado_ate    = IF(tentativas_login + 1 >= 5,
                            NOW() + INTERVAL 15 MINUTE,   -- ADAPTAR: tempo
                            bloqueado_ate),
      tentativas_login = IF(tentativas_login + 1 >= 5,
                            0,                            -- zera ao bloquear
                            tentativas_login + 1)         -- ADAPTAR: limite 5
  WHERE email = p_email;
END$$
-- 5.2 Login correto: zera o contador e remove bloqueio temporário
DROP PROCEDURE IF EXISTS sp_login_ok$$
CREATE PROCEDURE sp_login_ok(IN p_usuario_id INT UNSIGNED) BEGIN UPDATE usuarios SET tentativas_login = 0, bloqueado_ate    = NULL WHERE id = p_usuario_id; END$$ /* ===================================================================== 6. PROCEDURES DE NOTAS  (RF-03, RF-05, RF-06, RN-03, RN-04, RN-06)
   O back-end chama estas procedures em vez de escrever INSERT/UPDATE
   direto. Cada uma: (1) confere a permissão, (2) informa quem está
   agindo, (3) altera. O trigger da seção 4 grava o histórico.
   Erros usam SQLSTATE '45000' com mensagem; o back-end pode traduzir
   para HTTP 403 / 404.
   ===================================================================== */
-- 6.1 Criar nota (devolve o id gerado)
DROP PROCEDURE IF EXISTS sp_criar_nota$$
CREATE PROCEDURE sp_criar_nota(IN p_usuario_id INT UNSIGNED, IN p_titulo     VARCHAR(200),
                               IN p_conteudo   MEDIUMTEXT)
BEGIN
  SET @usuario_id_atual = p_usuario_id;
  SET @acao_historico   = NULL;
INSERT INTO notas (dono_id, titulo, conteudo)
  VALUES (p_usuario_id, p_titulo, COALESCE(p_conteudo, ''));
SELECT LAST_INSERT_ID() AS nota_id;
END$$
-- 6.2 Editar nota (dono ou quem tem permissão 'edicao')
DROP PROCEDURE IF EXISTS sp_editar_nota$$
CREATE PROCEDURE sp_editar_nota(IN p_usuario_id INT UNSIGNED, IN p_nota_id    INT UNSIGNED, IN p_titulo     VARCHAR(200),
                                IN p_conteudo   MEDIUMTEXT)
BEGIN
  DECLARE v_permissao VARCHAR(10);
  SET v_permissao = fn_permissao_nota(p_nota_id, p_usuario_id);
IF v_permissao IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RNF-04: acesso negado a esta nota (403)';
  ELSEIF v_permissao = 'leitura' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-04: voce tem apenas permissao de leitura';
  END IF;
SET @usuario_id_atual = p_usuario_id;
  SET @acao_historico   = NULL;
UPDATE notas
  SET titulo = p_titulo, conteudo = COALESCE(p_conteudo, '')
  WHERE id = p_nota_id;
END$$
-- 6.3 Excluir nota (somente o DONO; exclusão lógica)
DROP PROCEDURE IF EXISTS sp_excluir_nota$$
CREATE PROCEDURE sp_excluir_nota(IN p_usuario_id INT UNSIGNED, IN p_nota_id    INT UNSIGNED)
BEGIN
  IF fn_permissao_nota(p_nota_id, p_usuario_id) <> 'dono'
     OR fn_permissao_nota(p_nota_id, p_usuario_id) IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-03: somente o dono pode excluir a nota';
  END IF;
SET @usuario_id_atual = p_usuario_id;
  SET @acao_historico   = NULL;
UPDATE notas
  SET excluida = 1, excluida_em = NOW()      -- RN-06: nunca usar DELETE
  WHERE id = p_nota_id;
END$$
-- 6.4 Restaurar versão anterior (RF-06)
-- p_historico_id = id da linha de historico_alteracoes cuja versão
-- ANTERIOR (titulo_anterior / conteudo_anterior) deve voltar a valer.
DROP PROCEDURE IF EXISTS sp_restaurar_versao$$
CREATE PROCEDURE sp_restaurar_versao(IN p_historico_id BIGINT UNSIGNED, IN p_usuario_id   INT UNSIGNED)
BEGIN
  DECLARE v_nota_id   INT UNSIGNED DEFAULT NULL;
  DECLARE v_titulo    VARCHAR(200);
  DECLARE v_conteudo  MEDIUMTEXT;
  DECLARE v_permissao VARCHAR(10);
  SELECT nota_id, titulo_anterior, conteudo_anterior INTO v_nota_id, v_titulo, v_conteudo
  FROM historico_alteracoes
  WHERE id = p_historico_id AND conteudo_anterior IS NOT NULL;
IF v_nota_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Versao nao encontrada no historico (404)';
  END IF;
SET v_permissao = fn_permissao_nota(v_nota_id, p_usuario_id);
  IF v_permissao IS NULL OR v_permissao = 'leitura' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-04: sem permissao de edicao para restaurar';
  END IF;
SET @usuario_id_atual = p_usuario_id;
  SET @acao_historico   = 'restauracao';     -- o trigger lê esta variável
UPDATE notas SET titulo = v_titulo, conteudo = v_conteudo
  WHERE id = v_nota_id;
SET @acao_historico = NULL;                -- limpa para não "vazar"
END$$
/* =====================================================================
   7. PROCEDURES DE COMPARTILHAMENTO E TEMAS  (RF-04, RF-08, RN-07)
   ===================================================================== */
-- 7.1 Compartilhar (ou alterar a permissão de) uma nota - só o DONO
DROP PROCEDURE IF EXISTS sp_compartilhar_nota$$
CREATE PROCEDURE sp_compartilhar_nota(IN p_dono_id         INT UNSIGNED, IN p_nota_id         INT UNSIGNED, IN p_email_convidado VARCHAR(150),
                                      IN p_permissao       VARCHAR(10))
BEGIN
  DECLARE v_convidado_id INT UNSIGNED DEFAULT NULL;
IF p_permissao NOT IN ('leitura','edicao') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Permissao invalida: use leitura ou edicao';
  END IF;
IF NOT EXISTS (SELECT 1 FROM notas
                 WHERE id = p_nota_id AND dono_id = p_dono_id AND excluida = 0) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-03: somente o dono altera o compartilhamento';
  END IF;
SET v_convidado_id = (SELECT id FROM usuarios
                        WHERE email = p_email_convidado AND bloqueado = 0
                        LIMIT 1);
IF v_convidado_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Usuario convidado nao encontrado';
  END IF;
IF v_convidado_id = p_dono_id THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'O dono ja tem acesso total a nota';
  END IF;
-- Se já existir compartilhamento, apenas atualiza a permissão.
  INSERT INTO compartilhamentos (nota_id, usuario_id, permissao)
  VALUES (p_nota_id, v_convidado_id, p_permissao)
  ON DUPLICATE KEY UPDATE permissao = p_permissao;
END$$
-- 7.2 Remover compartilhamento - só o DONO
DROP PROCEDURE IF EXISTS sp_descompartilhar_nota$$
CREATE PROCEDURE sp_descompartilhar_nota(IN p_dono_id    INT UNSIGNED, IN p_nota_id    INT UNSIGNED, IN p_usuario_id INT UNSIGNED)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM notas
                 WHERE id = p_nota_id AND dono_id = p_dono_id AND excluida = 0) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-03: somente o dono altera o compartilhamento';
  END IF;
DELETE FROM compartilhamentos
  WHERE nota_id = p_nota_id AND usuario_id = p_usuario_id;
END$$
-- 7.3 Excluir tema (RN-07)
-- Se o tema tem notas vinculadas, só exclui com p_confirmar = 1.
-- As notas NÃO são apagadas; apenas perdem a ligação com o tema.
DROP PROCEDURE IF EXISTS sp_excluir_tema$$
CREATE PROCEDURE sp_excluir_tema(IN p_usuario_id INT UNSIGNED, IN p_tema_id    INT UNSIGNED, IN p_confirmar  TINYINT)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM temas
                 WHERE id = p_tema_id AND usuario_id = p_usuario_id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Tema nao encontrado ou nao pertence ao usuario';
  END IF;
IF EXISTS (SELECT 1 FROM notas_temas WHERE tema_id = p_tema_id)
     AND COALESCE(p_confirmar, 0) = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'RN-07: tema possui notas; confirme para excluir';
  END IF;
DELETE FROM notas_temas WHERE tema_id = p_tema_id;
  DELETE FROM temas       WHERE id = p_tema_id;
END$$
DELIMITER ;
/* =====================================================================
   8. VIEWS  (consultas reutilizáveis)
   View = "consulta salva" com nome. Útil para o back-end não repetir
   JOINs. ADAPTAR: se adicionar colunas nas tabelas, inclua-as aqui.
   ===================================================================== */
-- 8.1 Histórico legível: mostra o NOME do autor e o título da nota (RF-05)
CREATE OR REPLACE VIEW vw_historico_detalhado AS
  SELECT h.id          AS historico_id, h.nota_id, n.titulo      AS titulo_atual_da_nota,
  u.nome        AS autor, h.acao, h.titulo_anterior,
  h.conteudo_anterior, h.criado_em   AS data_hora
FROM historico_alteracoes h
JOIN usuarios u ON u.id = h.usuario_id
JOIN notas    n ON n.id = h.nota_id;
-- 8.2 Temas com a quantidade de notas ativas (alimenta a lista de temas)
CREATE OR REPLACE VIEW vw_temas_resumo AS
  SELECT t.id        AS tema_id, t.usuario_id, t.nome      AS tema,
  COUNT(n.id) AS total_notas
FROM temas t
LEFT JOIN notas_temas nt ON nt.tema_id = t.id
LEFT JOIN notas n        ON n.id = nt.nota_id AND n.excluida = 0
GROUP BY t.id, t.usuario_id, t.nome;
/* =====================================================================
   9. DADOS DE EXEMPLO  (somente desenvolvimento / testes)
   Os ids abaixo assumem um banco recém-criado (1, 2, 3...).
   Os hashes são FICTÍCIOS: em uso real o back-end gera com bcrypt.
   Não execute duas vezes (e-mails são únicos).
   ===================================================================== */
INSERT INTO usuarios (nome, email, senha_hash, perfil) VALUES
  ('Administrador', 'admin@senai.exemplo', '$2b$10$HASH_FICTICIO_SUBSTITUA_PELO_BCRYPT_REAL', 'administrador'),
  ('Profa. Maria',  'maria@senai.exemplo', '$2b$10$HASH_FICTICIO_SUBSTITUA_PELO_BCRYPT_REAL', 'instrutor'),
  ('Joao Aluno',    'joao@senai.exemplo',  '$2b$10$HASH_FICTICIO_SUBSTITUA_PELO_BCRYPT_REAL', 'aluno');
-- Temas da Profa. Maria (usuario 2)
INSERT INTO temas (usuario_id, nome) VALUES
  (2, 'Banco de Dados'),
  (2, 'Projeto Integrador');
-- Notas (as procedures já informam o autor ao histórico)
CALL sp_criar_nota(2, 'Aula 01 - Modelagem',  'Entidades, atributos e relacionamentos.');
CALL sp_criar_nota(2, 'Aula 02 - SQL basico', 'SELECT, INSERT, UPDATE e DELETE.');
-- Ligação nota <-> tema
INSERT INTO notas_temas (nota_id, tema_id) VALUES (1, 1), (2, 1), (2, 2);
-- Compartilhamento: João pode EDITAR a nota 1 e só LER a nota 2
CALL sp_compartilhar_nota(2, 1, 'joao@senai.exemplo', 'edicao');
CALL sp_compartilhar_nota(2, 2, 'joao@senai.exemplo', 'leitura');
-- João edita a nota 1 (gera histórico com autor = João)
CALL sp_editar_nota(3, 1, 'Aula 01 - Modelagem', 'Entidades, atributos, relacionamentos e cardinalidade.');
-- TESTE DA RN-04 (deve dar erro, pois João só tem leitura na nota 2):
-- CALL sp_editar_nota(3, 2, 'Tentativa', 'nao deve funcionar');
-- Abas abertas do João (opcional)
INSERT INTO abas_abertas (usuario_id, nota_id, posicao, ativa) VALUES
  (3, 1, 0, 1),
  (3, 2, 1, 0);
/* =====================================================================
   10. CONSULTAS PRONTAS PARA O BACK-END
   Em Node/Express use "?" no lugar das variáveis (consultas
   parametrizadas) para evitar SQL Injection. Aqui usamos variáveis
   de sessão do MySQL apenas para você poder testar no Workbench.
   ===================================================================== */
SET @uid = 3;                 -- id do usuário logado (exemplo: João)
SET @email = 'joao@senai.exemplo';
-- 10.1 LOGIN (RF-02, RN-10): traz o usuário só se NÃO estiver bloqueado.
-- O back-end compara a senha digitada com senha_hash usando bcrypt.
SELECT id, nome, perfil, senha_hash
FROM usuarios
WHERE email = @email
  AND bloqueado = 0
  AND (bloqueado_ate IS NULL OR bloqueado_ate <= NOW());
-- 10.2 MINHAS NOTAS: próprias + compartilhadas, com a permissão (RF-03/04)
SELECT n.id, n.titulo, 'dono' AS permissao, n.atualizado_em
FROM notas n
WHERE n.dono_id = @uid AND n.excluida = 0
UNION ALL
SELECT n.id, n.titulo, c.permissao, n.atualizado_em
FROM notas n
JOIN compartilhamentos c ON c.nota_id = n.id
WHERE c.usuario_id = @uid AND n.excluida = 0
ORDER BY titulo;
-- 10.3 ABRIR UMA NOTA (valida acesso; sem linha = erro 403)
SET @nota = 1;
SELECT n.id, n.titulo, n.conteudo, fn_permissao_nota(n.id, @uid) AS permissao
FROM notas n
WHERE n.id = @nota
  AND fn_permissao_nota(n.id, @uid) IS NOT NULL;
-- 10.4 LISTA DE TEMAS do usuário (RF-08)
SELECT tema_id, tema, total_notas
FROM vw_temas_resumo
WHERE usuario_id = 2        -- tema pertence a Profa. Maria neste exemplo
ORDER BY tema;
-- 10.5 NOTAS DE UM TEMA - usado no "redirecionar direto ao tema" (RF-08)
-- Só devolve notas que o usuário pode acessar.
SET @tema = 1;
SELECT n.id, n.titulo
FROM notas_temas nt
JOIN notas n ON n.id = nt.nota_id
WHERE nt.tema_id = @tema
  AND n.excluida = 0
  AND fn_permissao_nota(n.id, @uid) IS NOT NULL
ORDER BY n.titulo;
-- 10.6 BUSCA (RF-09): FULLTEXT por título/conteúdo, só notas acessíveis.
-- Obs.: FULLTEXT ignora palavras com menos de 3 letras (padrão InnoDB).
-- Para termos curtos, use LIKE como alternativa (exemplo logo abaixo).
SET @termo = 'modelagem';
  SELECT n.id, n.titulo, MATCH(n.titulo, n.conteudo) AGAINST (@termo IN NATURAL LANGUAGE MODE) AS relevancia
FROM notas n
WHERE n.excluida = 0
  AND fn_permissao_nota(n.id, @uid) IS NOT NULL
  AND MATCH(n.titulo, n.conteudo) AGAINST (@termo IN NATURAL LANGUAGE MODE)
ORDER BY relevancia DESC;
-- Alternativa com LIKE (mais lenta, mas aceita termos curtos):
-- SELECT n.id, n.titulo FROM notas n
-- WHERE n.excluida = 0 AND fn_permissao_nota(n.id, @uid) IS NOT NULL
--   AND (n.titulo LIKE CONCAT('%', @termo, '%') OR n.conteudo LIKE CONCAT('%', @termo, '%'));
-- 10.7 HISTÓRICO DE UMA NOTA em ordem cronológica (RF-05)
-- Antes, o back-end confere o acesso (consulta 10.3 ou fn_permissao_nota).
SELECT historico_id, autor, acao, data_hora
FROM vw_historico_detalhado
WHERE nota_id = @nota
ORDER BY data_hora, historico_id;
-- 10.8 RESTAURAR UMA VERSÃO (RF-06): use o historico_id da consulta acima
-- CALL sp_restaurar_versao(1, @uid);
-- 10.9 ABAS (RF-07, opcional)
-- Abrir/focar uma aba (se já existir, só marca como ativa):
UPDATE abas_abertas SET ativa = 0 WHERE usuario_id = @uid;
INSERT INTO abas_abertas (usuario_id, nota_id, posicao, ativa)
VALUES (@uid, @nota, 0, 1)
ON DUPLICATE KEY UPDATE ativa = 1;
-- Listar abas do usuário:
SELECT a.nota_id, n.titulo, a.ativa
FROM abas_abertas a
JOIN notas n ON n.id = a.nota_id
WHERE a.usuario_id = @uid AND n.excluida = 0
ORDER BY a.posicao;
-- Fechar uma aba:
-- DELETE FROM abas_abertas WHERE usuario_id = @uid AND nota_id = @nota;
-- 10.10 ADMINISTRADOR (RF-10)
-- Listar usuários:
-- SELECT id, nome, email, perfil, bloqueado FROM usuarios ORDER BY nome;
-- Bloquear / desbloquear / alterar perfil:
-- UPDATE usuarios SET bloqueado = 1 WHERE id = 3;
-- UPDATE usuarios SET bloqueado = 0, tentativas_login = 0, bloqueado_ate = NULL WHERE id = 3;
-- UPDATE usuarios SET perfil = 'instrutor' WHERE id = 3;
/* =====================================================================
   11. GUIA DE ADAPTAÇÕES (receitas prontas)
   ---------------------------------------------------------------------
   A) ADICIONAR UMA COLUNA (ex.: cor da nota)
        ALTER TABLE notas ADD COLUMN cor VARCHAR(7) NULL AFTER conteudo;
      Se a coluna deve ser versionada no histórico, adicione também
      "cor_anterior" em historico_alteracoes e inclua-a no trigger
      trg_notas_au (INSERT e comparação de mudança).
B) NOVO PERFIL DE USUÁRIO (ex.: 'coordenador')
        ALTER TABLE usuarios MODIFY perfil
          ENUM('aluno','instrutor','coordenador','administrador')
          NOT NULL DEFAULT 'aluno';
C) NOVA PERMISSÃO DE COMPARTILHAMENTO (ex.: 'comentario')
        ALTER TABLE compartilhamentos MODIFY permissao
          ENUM('leitura','comentario','edicao') NOT NULL DEFAULT 'leitura';
      Depois ajuste: fn_permissao_nota (nada muda, só devolve o valor),
      sp_editar_nota (quem pode editar) e a validação em
      sp_compartilhar_nota (lista de permissões válidas).
D) NOVA AÇÃO NO HISTÓRICO (ex.: 'compartilhamento')
        ALTER TABLE historico_alteracoes MODIFY acao
          ENUM('criacao','edicao','exclusao','restauracao','compartilhamento') NOT NULL;
      Crie um trigger AFTER INSERT em compartilhamentos que grave a ação.
E) MUDAR O LIMITE DE TENTATIVAS / TEMPO DE BLOQUEIO (RN-10)
      Edite os números 5 e 15 em sp_login_falho:
        DROP PROCEDURE sp_login_falho;  -- e recrie com os novos valores
F) LIMITAR TAMANHO DA NOTA
        ALTER TABLE notas MODIFY conteudo TEXT NOT NULL;   -- até 64 KB
G) TEMAS COMPARTILHADOS POR GRUPO
      Crie "grupos" e "grupos_usuarios", troque temas.usuario_id por
      grupo_id e ajuste UNIQUE (grupo_id, nome) e sp_excluir_tema.
H) RETENÇÃO DO HISTÓRICO (ex.: manter 2 anos)
        -- 1) DROP TRIGGER trg_historico_bd;
        -- 2) DELETE FROM historico_alteracoes
        --      WHERE criado_em < NOW() - INTERVAL 2 YEAR;
        -- 3) recrie trg_historico_bd (seção 4.3)
I) BOA PRÁTICA GERAL
      - Antes de qualquer ALTER em produção, faça backup (RNF-06):
          mysqldump -u usuario -p bloco_notas > backup_bloco_notas.sql
      - Nunca grave senha em texto puro (RNF-02).
      - Sempre use consultas parametrizadas no back-end.
      - Teste mudanças primeiro em um banco de desenvolvimento.
   ===================================================================== */
