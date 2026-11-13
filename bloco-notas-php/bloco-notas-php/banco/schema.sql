/* =====================================================================
   BLOCO DE NOTAS COMPARTILHADO - SENAI JOINVILLE
   Banco de dados PostgreSQL 12+  (versão do script MySQL do projeto)
   ---------------------------------------------------------------------
   COMO LER ESTE SCRIPT
   O arquivo está dividido em seções numeradas. Cada seção diz:
     - O QUE ela cria
     - QUAL requisito (RF / RNF / RN da ficha) ela atende
     - COMO adaptar caso o projeto mude

   COMO EXECUTAR (uma vez só)
     1) Crie o banco (isso é feito FORA deste script, no psql):
          psql -U postgres -c "CREATE DATABASE bloco_notas ENCODING 'UTF8'"
     2) Rode este arquivo dentro do banco criado:
          psql -U postgres -d bloco_notas -f banco/schema.sql
     3) Rode o script de exemplo (opcional):
          php banco/semear.php

   SEÇÕES
     1. Convenções
     2. Tabelas (usuarios, temas, notas, notas_temas,
        compartilhamentos, abas_abertas, historico_alteracoes)
     3. Funções (permissão da nota e utilitários)
     4. Triggers (histórico automático, proteção do histórico)
     5. Views
     6. Consultas úteis para testar no psql
     7. Guia de adaptações

   O QUE MUDOU EM RELAÇÃO À VERSÃO MySQL (resumo)
     - ENUM            -> VARCHAR + CHECK (mais fácil de alterar depois)
     - AUTO_INCREMENT  -> GENERATED ALWAYS AS IDENTITY
     - TINYINT(1)      -> BOOLEAN (TRUE / FALSE)
     - MEDIUMTEXT      -> TEXT (sem limite prático)
     - ON UPDATE CURRENT_TIMESTAMP -> trigger trg_fn_atualizado_em
     - @usuario_id_atual (variável de sessão) -> set_config('app.usuario_id', ...)
     - FULLTEXT        -> índice GIN com to_tsvector('portuguese', ...)
     - PROCEDUREs sp_* -> viraram funções PHP em src/modelos/
       (mapa completo no README.md). O banco continua garantindo as
       regras que NÃO podem falhar: unicidade, chaves estrangeiras,
       histórico automático e histórico imutável.
   ===================================================================== */

/* =====================================================================
   1. CONVENÇÕES (mantenha ao adaptar)
     - nomes de tabelas no plural e em minúsculas
     - chave primária sempre "id"
     - chave estrangeira = <tabela_no_singular>_id
     - criado_em / atualizado_em em tabelas que mudam
     - ordem importa: tabelas "pai" antes das tabelas "filhas"
   ===================================================================== */

-- Para recomeçar do zero em DESENVOLVIMENTO, apague e recrie o banco:
--   DROP DATABASE bloco_notas;  (rode conectado a OUTRO banco, ex.: postgres)

/* =====================================================================
   2. TABELAS
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 2.1 USUARIOS  (RF-01, RF-02, RF-10, RN-01, RN-09, RN-10, RNF-02)
-- A senha NUNCA é guardada em texto puro: o PHP gera o hash com
-- password_hash() (bcrypt) e grava aqui em senha_hash.
-- A regra de senha mínima (RN-09) é validada no PHP (config.php).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
  id                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome              VARCHAR(100) NOT NULL,
  email             VARCHAR(150) NOT NULL,
  senha_hash        VARCHAR(255) NOT NULL,
  perfil            VARCHAR(20)  NOT NULL DEFAULT 'aluno',
  bloqueado         BOOLEAN      NOT NULL DEFAULT FALSE,   -- bloqueio manual (RF-10)
  tentativas_login  SMALLINT     NOT NULL DEFAULT 0,       -- RN-10
  bloqueado_ate     TIMESTAMP    NULL,                     -- RN-10 (temporário)
  criado_em         TIMESTAMP    NOT NULL DEFAULT now(),
  atualizado_em     TIMESTAMP    NOT NULL DEFAULT now(),
  -- ADAPTAR: novos perfis entram nesta lista (ver guia, item B)
  CONSTRAINT ck_usuarios_perfil
    CHECK (perfil IN ('aluno','instrutor','administrador'))
);
-- RN-01: e-mail único, sem diferenciar maiúsculas de minúsculas.
CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_email ON usuarios (lower(email));

-- ---------------------------------------------------------------------
-- 2.2 TEMAS  (RF-08, RN-08)
-- Cada tema pertence a um usuário; o nome é único POR usuário.
-- ADAPTAR: para temas compartilhados por grupo, crie a tabela "grupos"
-- e troque usuario_id por grupo_id (e o UNIQUE também).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS temas (
  id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id  INTEGER     NOT NULL,
  nome        VARCHAR(80) NOT NULL,
  criado_em   TIMESTAMP   NOT NULL DEFAULT now(),
  CONSTRAINT uq_temas_usuario_nome UNIQUE (usuario_id, nome),   -- RN-08
  CONSTRAINT fk_temas_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 2.3 NOTAS  (RF-03, RN-03, RN-06, RF-09)
-- Exclusão LÓGICA (RN-06): a nota nunca some do banco, só recebe
-- excluida = TRUE. Assim o histórico continua existindo.
-- O limite de tamanho está em aberto na ficha ("validar com o
-- cliente"): TEXT aceita até ~1 GB. ADAPTAR: veja o guia, item F.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas (
  id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  dono_id        INTEGER      NOT NULL,                  -- RN-03: quem criou é o dono
  titulo         VARCHAR(200) NOT NULL,
  conteudo       TEXT         NOT NULL DEFAULT '',       -- '' = nota vazia
  excluida       BOOLEAN      NOT NULL DEFAULT FALSE,    -- RN-06
  excluida_em    TIMESTAMP    NULL,
  criado_em      TIMESTAMP    NOT NULL DEFAULT now(),
  atualizado_em  TIMESTAMP    NOT NULL DEFAULT now(),
  CONSTRAINT fk_notas_dono FOREIGN KEY (dono_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
);
-- acelera "minhas notas"
CREATE INDEX IF NOT EXISTS idx_notas_dono ON notas (dono_id, excluida);
-- RF-09: busca de texto completo (equivalente ao FULLTEXT do MySQL).
-- A consulta em src/modelos/notas.php usa EXATAMENTE esta expressão.
CREATE INDEX IF NOT EXISTS ft_notas_busca ON notas
  USING GIN (to_tsvector('portuguese', titulo || ' ' || conteudo));

-- ---------------------------------------------------------------------
-- 2.4 NOTAS_TEMAS  (RF-08, RN-07)
-- Tabela de ligação N:N: uma nota pode ter vários temas e um tema pode
-- ter várias notas. A chave primária composta evita duplicidade.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notas_temas (
  nota_id  INTEGER NOT NULL,
  tema_id  INTEGER NOT NULL,
  PRIMARY KEY (nota_id, tema_id),
  CONSTRAINT fk_nt_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE CASCADE,
  -- RESTRICT: não deixa apagar um tema que ainda tem notas (RN-07).
  -- Para excluir com confirmação, use tema_excluir() no PHP.
  CONSTRAINT fk_nt_tema FOREIGN KEY (tema_id)
    REFERENCES temas (id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 2.5 COMPARTILHAMENTOS  (RF-04, RN-03, RN-04)
-- Uma linha = "este usuário tem esta permissão nesta nota".
-- O DONO não precisa de linha aqui (ele já é o dono em notas.dono_id).
-- ADAPTAR: nova permissão (ex.: 'comentario') = guia, item C.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS compartilhamentos (
  id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nota_id     INTEGER     NOT NULL,
  usuario_id  INTEGER     NOT NULL,                       -- quem recebeu o acesso
  permissao   VARCHAR(10) NOT NULL DEFAULT 'leitura',
  criado_em   TIMESTAMP   NOT NULL DEFAULT now(),
  CONSTRAINT ck_comp_permissao CHECK (permissao IN ('leitura','edicao')),
  CONSTRAINT uq_comp_nota_usuario UNIQUE (nota_id, usuario_id),
  CONSTRAINT fk_comp_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE CASCADE,
  CONSTRAINT fk_comp_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 2.6 ABAS_ABERTAS  (RF-07)  *** OPCIONAL / SEM TELA NESTA VERSÃO ***
-- A ficha trata as abas como recurso da interface. Esta tabela só é
-- necessária se o cliente quiser que as abas abertas voltem quando o
-- usuário entrar de novo. A aplicação PHP não a usa (as "abas" são as
-- abas do próprio navegador). Mantida para não perder a modelagem.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS abas_abertas (
  id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id  INTEGER  NOT NULL,
  nota_id     INTEGER  NOT NULL,
  posicao     SMALLINT NOT NULL DEFAULT 0,              -- ordem da aba
  ativa       BOOLEAN  NOT NULL DEFAULT FALSE,          -- aba selecionada
  aberta_em   TIMESTAMP NOT NULL DEFAULT now(),
  CONSTRAINT uq_abas_usuario_nota UNIQUE (usuario_id, nota_id),
  CONSTRAINT fk_abas_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE CASCADE,
  CONSTRAINT fk_abas_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE CASCADE
);

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
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nota_id           INTEGER     NOT NULL,
  usuario_id        INTEGER     NOT NULL,                -- autor da alteração
  acao              VARCHAR(15) NOT NULL,
  titulo_anterior   VARCHAR(200) NULL,
  conteudo_anterior TEXT        NULL,
  criado_em         TIMESTAMP   NOT NULL DEFAULT now(),
  -- ADAPTAR: novas ações entram nesta lista (guia, item D)
  CONSTRAINT ck_hist_acao
    CHECK (acao IN ('criacao','edicao','exclusao','restauracao')),
  CONSTRAINT fk_hist_nota FOREIGN KEY (nota_id)
    REFERENCES notas (id) ON DELETE RESTRICT,
  CONSTRAINT fk_hist_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_hist_nota_data
  ON historico_alteracoes (nota_id, criado_em);

/* =====================================================================
   3. FUNÇÕES  (RNF-04, RN-03, RN-04, RN-05)
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 3.1 fn_permissao_nota
-- Centraliza a pergunta "o que este usuário pode fazer nesta nota?".
-- Retorna: 'dono' | 'edicao' | 'leitura' | NULL (sem acesso -> 403).
-- Nota inexistente ou excluída também retorna NULL.
-- Todo o PHP usa esta função, então uma regra nova de acesso é
-- alterada em UM lugar só.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_permissao_nota(p_nota_id INTEGER, p_usuario_id INTEGER)
RETURNS VARCHAR
LANGUAGE sql STABLE AS $$
  SELECT CASE
           WHEN n.dono_id = p_usuario_id THEN 'dono'
           ELSE (SELECT c.permissao
                   FROM compartilhamentos c
                  WHERE c.nota_id = n.id AND c.usuario_id = p_usuario_id)
         END
    FROM notas n
   WHERE n.id = p_nota_id AND n.excluida = FALSE;
$$;

-- ---------------------------------------------------------------------
-- 3.2 fn_usuario_atual
-- COMO O BANCO SABE QUEM ALTEROU?
-- O PHP abre uma transação e executa, ANTES de mexer em notas:
--     SELECT set_config('app.usuario_id', '<id do usuário>', true);
-- (a função transacao() em src/nucleo/db.php já faz isso por você).
-- O "true" significa "vale só até o fim desta transação".
-- Sem essa configuração, a alteração é recusada (garante a RN-05).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_usuario_atual()
RETURNS INTEGER
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v TEXT;
BEGIN
  v := current_setting('app.usuario_id', true);   -- true = não dá erro se não existir
  IF v IS NULL OR v = '' THEN
    RAISE EXCEPTION 'RN-05: defina app.usuario_id antes de alterar notas';
  END IF;
  RETURN v::INTEGER;
END $$;

/* =====================================================================
   4. TRIGGERS  (RF-05, RN-05)
   Triggers são "gatilhos": o próprio banco executa o código quando uma
   linha é inserida/alterada. Assim o histórico é gravado SEMPRE, mesmo
   que alguém esqueça de chamá-lo no PHP.
   Em PostgreSQL um trigger tem 2 partes: a FUNÇÃO (o que fazer) e o
   TRIGGER (quando executar).
   ===================================================================== */

-- 4.0 Mantém atualizado_em (substitui o ON UPDATE CURRENT_TIMESTAMP)
CREATE OR REPLACE FUNCTION trg_fn_atualizado_em() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_usuarios_bu ON usuarios;
CREATE TRIGGER trg_usuarios_bu BEFORE UPDATE ON usuarios
  FOR EACH ROW EXECUTE FUNCTION trg_fn_atualizado_em();

DROP TRIGGER IF EXISTS trg_notas_bu ON notas;
CREATE TRIGGER trg_notas_bu BEFORE UPDATE ON notas
  FOR EACH ROW EXECUTE FUNCTION trg_fn_atualizado_em();

-- 4.1 Nova nota -> registra 'criacao'
CREATE OR REPLACE FUNCTION trg_fn_notas_ai() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO historico_alteracoes (nota_id, usuario_id, acao)
  VALUES (NEW.id, fn_usuario_atual(), 'criacao');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notas_ai ON notas;
CREATE TRIGGER trg_notas_ai AFTER INSERT ON notas
  FOR EACH ROW EXECUTE FUNCTION trg_fn_notas_ai();

-- 4.2 Nota alterada -> registra 'edicao', 'exclusao' ou 'restauracao'
CREATE OR REPLACE FUNCTION trg_fn_notas_au() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_acao VARCHAR(15) := NULL;
BEGIN
  IF OLD.excluida = FALSE AND NEW.excluida = TRUE THEN
    v_acao := 'exclusao';
  ELSIF NEW.titulo IS DISTINCT FROM OLD.titulo
     OR NEW.conteudo IS DISTINCT FROM OLD.conteudo THEN
    -- app.acao_historico = 'restauracao' é definido pelo PHP em
    -- historico_restaurar(); nos demais casos é uma edição comum.
    v_acao := COALESCE(NULLIF(current_setting('app.acao_historico', true), ''), 'edicao');
  END IF;

  -- Se nada relevante mudou (ex.: só atualizado_em), não registra nada.
  IF v_acao IS NOT NULL THEN
    INSERT INTO historico_alteracoes
      (nota_id, usuario_id, acao, titulo_anterior, conteudo_anterior)
    VALUES
      (OLD.id, fn_usuario_atual(), v_acao, OLD.titulo, OLD.conteudo);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notas_au ON notas;
CREATE TRIGGER trg_notas_au AFTER UPDATE ON notas
  FOR EACH ROW EXECUTE FUNCTION trg_fn_notas_au();

-- 4.3 Histórico é imutável (RN-05): proíbe UPDATE e DELETE
CREATE OR REPLACE FUNCTION trg_fn_historico_imutavel() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'RN-05: registros de historico nao podem ser editados nem apagados';
END $$;

DROP TRIGGER IF EXISTS trg_historico_bud ON historico_alteracoes;
CREATE TRIGGER trg_historico_bud BEFORE UPDATE OR DELETE ON historico_alteracoes
  FOR EACH ROW EXECUTE FUNCTION trg_fn_historico_imutavel();
-- ADAPTAR: se um dia for preciso limpar o histórico (retenção), veja
-- o guia, item H.

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
    LEFT JOIN notas n        ON n.id = nt.nota_id AND n.excluida = FALSE
   GROUP BY t.id, t.usuario_id, t.nome;

/* =====================================================================
   6. CONSULTAS ÚTEIS PARA TESTAR NO psql
   (a aplicação PHP usa versões parametrizadas destas consultas)
   ---------------------------------------------------------------------
   -- Quem sou eu? (troque 3 pelo id do usuário)
   --   \set uid 3
   -- Minhas notas (próprias + compartilhadas) com a permissão:
   --   SELECT id, titulo, fn_permissao_nota(id, :uid) AS permissao
   --     FROM notas
   --    WHERE excluida = FALSE AND fn_permissao_nota(id, :uid) IS NOT NULL;
   -- Busca (RF-09):
   --   SELECT id, titulo FROM notas
   --    WHERE to_tsvector('portuguese', titulo || ' ' || conteudo)
   --          @@ plainto_tsquery('portuguese', 'modelagem');
   -- Histórico de uma nota (RF-05):
   --   SELECT * FROM vw_historico_detalhado WHERE nota_id = 1
   --    ORDER BY data_hora, historico_id;
   -- Testar a RN-05 (deve dar ERRO, pois não há usuário informado):
   --   UPDATE notas SET titulo = 'x' WHERE id = 1;
   ===================================================================== */

/* =====================================================================
   7. GUIA DE ADAPTAÇÕES (receitas prontas)
   ---------------------------------------------------------------------
   A) ADICIONAR UMA COLUNA (ex.: cor da nota)
        ALTER TABLE notas ADD COLUMN cor VARCHAR(7) NULL;
      Depois: inclua a coluna nos SELECT/INSERT/UPDATE de
      src/modelos/notas.php e no formulário src/visoes/notas/form.php.
      Se a coluna deve ser versionada no histórico, adicione também
      "cor_anterior" em historico_alteracoes e inclua-a em
      trg_fn_notas_au (no INSERT e na comparação de mudança).

   B) NOVO PERFIL DE USUÁRIO (ex.: 'coordenador')
        ALTER TABLE usuarios DROP CONSTRAINT ck_usuarios_perfil;
        ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_perfil
          CHECK (perfil IN ('aluno','instrutor','coordenador','administrador'));
      Depois: acrescente o perfil na constante PERFIS de
      src/modelos/usuarios.php.

   C) NOVA PERMISSÃO DE COMPARTILHAMENTO (ex.: 'comentario')
        ALTER TABLE compartilhamentos DROP CONSTRAINT ck_comp_permissao;
        ALTER TABLE compartilhamentos ADD CONSTRAINT ck_comp_permissao
          CHECK (permissao IN ('leitura','comentario','edicao'));
      Depois ajuste em src/modelos/: a lista de permissões válidas em
      compartilhar_nota() e quem pode editar em nota_editar().
      fn_permissao_nota não muda (só devolve o valor).

   D) NOVA AÇÃO NO HISTÓRICO (ex.: 'compartilhamento')
        ALTER TABLE historico_alteracoes DROP CONSTRAINT ck_hist_acao;
        ALTER TABLE historico_alteracoes ADD CONSTRAINT ck_hist_acao
          CHECK (acao IN ('criacao','edicao','exclusao','restauracao','compartilhamento'));
      Crie um trigger AFTER INSERT em compartilhamentos que grave a ação.

   E) MUDAR O LIMITE DE TENTATIVAS / TEMPO DE BLOQUEIO (RN-10)
      Não mexe no banco: edite login_max_tentativas e
      login_bloqueio_minutos em config/config.php.

   F) LIMITAR TAMANHO DA NOTA
        ALTER TABLE notas ADD CONSTRAINT ck_notas_tamanho
          CHECK (length(conteudo) <= 65000);

   G) TEMAS COMPARTILHADOS POR GRUPO
      Crie "grupos" e "grupos_usuarios", troque temas.usuario_id por
      grupo_id e ajuste UNIQUE (grupo_id, nome) e tema_excluir().

   H) RETENÇÃO DO HISTÓRICO (ex.: manter 2 anos)
        -- 1) DROP TRIGGER trg_historico_bud ON historico_alteracoes;
        -- 2) DELETE FROM historico_alteracoes
        --     WHERE criado_em < now() - INTERVAL '2 years';
        -- 3) recrie o trigger (seção 4.3)

   I) BOA PRÁTICA GERAL
      - Antes de qualquer ALTER em produção, faça backup (RNF-06):
          pg_dump -U postgres -d bloco_notas -f backup_bloco_notas.sql
      - Nunca grave senha em texto puro (RNF-02).
      - Sempre use consultas parametrizadas no PHP (nunca concatene
        dados do usuário dentro do SQL).
      - Teste mudanças primeiro em um banco de desenvolvimento.
   ===================================================================== */
