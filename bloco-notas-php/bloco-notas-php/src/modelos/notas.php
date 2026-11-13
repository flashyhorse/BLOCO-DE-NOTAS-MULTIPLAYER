<?php
/* =====================================================================
   MODELO: NOTAS  (RF-03, RF-08, RF-09, RN-03, RN-04, RN-06)
   (Antigas procedures MySQL: sp_criar_nota, sp_editar_nota,
    sp_excluir_nota + consultas 10.2, 10.3, 10.5 e 10.6.)

   COMO O HISTÓRICO É GRAVADO?
   Toda escrita em "notas" passa por transacao($uid, ...). Ela informa
   ao banco quem está agindo, e os TRIGGERS do schema.sql gravam o
   histórico sozinhos. Por isso NENHUMA função daqui insere em
   historico_alteracoes.

   ADAPTAR: nova coluna em notas (ex.: cor) -> inclua em nota_criar(),
   nota_editar() e nota_obter() (veja schema.sql, guia item A).
   ===================================================================== */

/** RN-04: 'dono' | 'edicao' | 'leitura' | null (sem acesso). Usa a função do banco. */
function nota_permissao(int $nota_id, int $uid): ?string
{
    $r = consultar_um('SELECT fn_permissao_nota(:n, :u) AS permissao', ['n' => $nota_id, 'u' => $uid]);
    return $r['permissao'];
}

function validar_titulo_nota(string $titulo): void
{
    if ($titulo === '' || mb_strlen($titulo) > 200) {
        throw new ErroApp('Informe um título de até 200 caracteres.');
    }
}

/**
 * Lista as notas que o usuário pode ver (próprias + compartilhadas).
 * $busca   -> RF-09: texto no título/conteúdo
 * $tema_id -> RF-08: só notas deste tema
 */
function notas_listar(int $uid, string $busca = '', ?int $tema_id = null): array
{
    $filtros = ['x.permissao IS NOT NULL'];   // sem permissão = sem acesso
    $params  = ['u' => $uid];

    if ($busca !== '') {
        // 1) busca de texto completo (usa o índice ft_notas_busca)
        // 2) OU ILIKE, que também acha termos curtos (ex.: "SQL")
        $like = '%' . addcslashes($busca, '%_\\') . '%';
        $filtros[] = "(to_tsvector('portuguese', x.titulo || ' ' || x.conteudo)
                         @@ plainto_tsquery('portuguese', :b1)
                       OR x.titulo ILIKE :b2 OR x.conteudo ILIKE :b3)";
        $params['b1'] = $busca;
        $params['b2'] = $like;
        $params['b3'] = $like;
    }
    if ($tema_id) {
        $filtros[] = 'EXISTS (SELECT 1 FROM notas_temas nt WHERE nt.nota_id = x.id AND nt.tema_id = :tema)';
        $params['tema'] = $tema_id;
    }

    $sql = 'SELECT x.id, x.titulo, x.permissao, x.dono_nome, x.atualizado_em
              FROM (SELECT n.id, n.titulo, n.conteudo, n.atualizado_em,
                           u.nome AS dono_nome,
                           fn_permissao_nota(n.id, :u) AS permissao
                      FROM notas n
                      JOIN usuarios u ON u.id = n.dono_id
                     WHERE n.excluida = FALSE) x
             WHERE ' . implode(' AND ', $filtros) . '
             ORDER BY x.atualizado_em DESC';

    return consultar($sql, $params);
}

/** Abre uma nota. 404 se não existe; 403 se o usuário não tem acesso (RNF-04). */
function nota_obter(int $id, int $uid): array
{
    $n = consultar_um(
        'SELECT n.id, n.dono_id, n.titulo, n.conteudo, n.criado_em, n.atualizado_em,
                u.nome AS dono_nome,
                fn_permissao_nota(n.id, :u) AS permissao
           FROM notas n
           JOIN usuarios u ON u.id = n.dono_id
          WHERE n.id = :n AND n.excluida = FALSE',
        ['u' => $uid, 'n' => $id]
    );
    if (!$n) {
        throw new ErroApp('Nota não encontrada.', 404);
    }
    if ($n['permissao'] === null) {
        throw new ErroApp('Você não tem acesso a esta nota.', 403);
    }
    return $n;
}

/** Temas ligados a uma nota: [['id' => 1, 'nome' => 'Banco de Dados'], ...] */
function nota_temas(int $nota_id): array
{
    return consultar(
        'SELECT t.id, t.nome
           FROM notas_temas nt
           JOIN temas t ON t.id = nt.tema_id
          WHERE nt.nota_id = :n
          ORDER BY t.nome',
        ['n' => $nota_id]
    );
}

/** Só os ids dos temas (para marcar os checkboxes do formulário). */
function nota_temas_ids(int $nota_id): array
{
    return array_map(fn($t) => (int) $t['id'], nota_temas($nota_id));
}

/** RF-03: cria nota. O dono é quem criou (RN-03). Devolve o id. */
function nota_criar(int $uid, string $titulo, string $conteudo, array $temas_ids = []): int
{
    validar_titulo_nota($titulo);

    return transacao($uid, function () use ($uid, $titulo, $conteudo, $temas_ids) {
        $r = consultar_um(
            'INSERT INTO notas (dono_id, titulo, conteudo) VALUES (:d, :t, :c) RETURNING id',
            ['d' => $uid, 't' => $titulo, 'c' => $conteudo]
        );
        $id = (int) $r['id'];
        nota_definir_temas($id, $uid, $temas_ids);
        return $id;
    });
}

/**
 * Edita título/conteúdo (dono ou quem tem permissão 'edicao').
 * $temas_ids = null  -> não mexe nos temas
 * $temas_ids = [...] -> troca os temas (só o DONO pode; para os outros é ignorado)
 */
function nota_editar(int $uid, int $id, string $titulo, string $conteudo, ?array $temas_ids = null): void
{
    validar_titulo_nota($titulo);

    $perm = nota_permissao($id, $uid);
    if ($perm === null) {
        throw new ErroApp('Você não tem acesso a esta nota.', 403);              // RNF-04
    }
    if ($perm === 'leitura') {
        throw new ErroApp('Você tem apenas permissão de leitura nesta nota.', 403);  // RN-04
    }

    transacao($uid, function () use ($uid, $id, $titulo, $conteudo, $temas_ids, $perm) {
        executar('UPDATE notas SET titulo = :t, conteudo = :c WHERE id = :id',
                 ['t' => $titulo, 'c' => $conteudo, 'id' => $id]);
        if ($perm === 'dono' && $temas_ids !== null) {
            nota_definir_temas($id, $uid, $temas_ids);
        }
    });
}

/** RN-06: exclusão LÓGICA (nunca DELETE). Só o dono (RN-03). */
function nota_excluir(int $uid, int $id): void
{
    if (nota_permissao($id, $uid) !== 'dono') {
        throw new ErroApp('Somente o dono pode excluir a nota.', 403);
    }
    transacao($uid, fn() => executar(
        'UPDATE notas SET excluida = TRUE, excluida_em = now() WHERE id = :id',
        ['id' => $id]
    ));
}

/**
 * Substitui os temas da nota pelos escolhidos.
 * Só aceita temas que pertencem ao dono (RN-08): um id de tema alheio é
 * simplesmente ignorado pelo "WHERE usuario_id = :d".
 * Chame sempre dentro de transacao().
 */
function nota_definir_temas(int $nota_id, int $dono_id, array $temas_ids): void
{
    executar('DELETE FROM notas_temas WHERE nota_id = :n', ['n' => $nota_id]);
    foreach (array_unique(array_map('intval', $temas_ids)) as $tema_id) {
        // CAST(... AS integer): sem ele o PostgreSQL não sabe o tipo do parâmetro no SELECT.
        executar(
            'INSERT INTO notas_temas (nota_id, tema_id)
             SELECT CAST(:n AS integer), id FROM temas WHERE id = :t AND usuario_id = :d',
            ['n' => $nota_id, 't' => $tema_id, 'd' => $dono_id]
        );
    }
}
