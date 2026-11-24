<?php
/* =====================================================================
   MODELO: NOTAS  (RF-03, RF-08, RF-09, RN-03, RN-04, RN-06)
   (Antigas procedures MySQL: sp_criar_nota, sp_editar_nota,
    sp_excluir_nota + consultas 10.2, 10.3, 10.5 e 10.6.)

   COMO O HISTÓRICO É GRAVADO?
   Toda escrita em "notas" acontece dentro de transacao(...) e chama
   historico_registrar() (modelos/historico.php) logo antes de alterar a
   nota, guardando a versão ANTERIOR. Se qualquer passo falhar, a
   transação inteira é desfeita: nota e histórico nunca ficam
   dessincronizados. (Não há triggers: veja o schema.sql.)

   COMO A PERMISSÃO É DECIDIDA?
   Em um único lugar: a expressão SQL_PERMISSAO abaixo. Todas as consultas
   de notas a reutilizam, então uma regra nova de acesso muda só aqui.

   ADAPTAR: nova coluna em notas (ex.: cor) -> inclua em nota_criar(),
   nota_editar() e nota_obter() (veja schema.sql, guia item A).
   ===================================================================== */

/**
 * RN-03/RN-04: pedaço de SQL que calcula a permissão de um usuário em uma
 * nota. Pressupõe os apelidos "n" (notas) e "c" (compartilhamentos) e:
 *     FROM notas n
 *     LEFT JOIN compartilhamentos c ON c.nota_id = n.id AND c.usuario_id = <usuário>
 * Resultado: 'dono' | 'edicao' | 'leitura' | NULL (sem acesso).
 * $param_dono é o NOME do parâmetro que carrega o id do usuário (sem os
 * dois-pontos). Use um nome diferente a cada uso na mesma consulta, pois o
 * MySQL não aceita o mesmo parâmetro nomeado duas vezes: u1, u2, u3...
 */
function sql_permissao(string $param_dono): string
{
    return "CASE WHEN n.dono_id = :{$param_dono} THEN 'dono' ELSE c.permissao END";
}

/** RN-04: 'dono' | 'edicao' | 'leitura' | null (sem acesso; nota inexistente ou excluída também dá null). */
function nota_permissao(int $nota_id, int $uid): ?string
{
    $r = consultar_um(
        'SELECT ' . sql_permissao('u1') . ' AS permissao
           FROM notas n
           LEFT JOIN compartilhamentos c ON c.nota_id = n.id AND c.usuario_id = :u2
          WHERE n.id = :n AND n.excluida = 0',
        ['u1' => $uid, 'u2' => $uid, 'n' => $nota_id]
    );
    return $r ? $r['permissao'] : null;
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
    // Só entra quem é dono OU recebeu compartilhamento (sem permissão = sem acesso).
    $filtros = ['n.excluida = 0', '(n.dono_id = :u3 OR c.id IS NOT NULL)'];
    $params  = ['u1' => $uid, 'u2' => $uid, 'u3' => $uid];

    if ($busca !== '') {
        // LIKE com a collation utf8mb4_unicode_ci: ignora maiúsculas e acentos
        // ("acao" acha "Ação") e aceita termos curtos (ex.: "SQL").
        // O \ antes de % e _ faz o usuário buscar esses caracteres literalmente.
        $like = '%' . addcslashes($busca, '%_\\') . '%';
        $filtros[] = '(n.titulo LIKE :b1 OR n.conteudo LIKE :b2)';
        $params['b1'] = $like;
        $params['b2'] = $like;
    }
    if ($tema_id) {
        $filtros[] = 'EXISTS (SELECT 1 FROM notas_temas nt WHERE nt.nota_id = n.id AND nt.tema_id = :tema)';
        $params['tema'] = $tema_id;
    }

    $sql = 'SELECT n.id, n.titulo, n.atualizado_em, u.nome AS dono_nome,
                   ' . sql_permissao('u1') . ' AS permissao
              FROM notas n
              JOIN usuarios u ON u.id = n.dono_id
              LEFT JOIN compartilhamentos c ON c.nota_id = n.id AND c.usuario_id = :u2
             WHERE ' . implode(' AND ', $filtros) . '
             ORDER BY n.atualizado_em DESC';

    return consultar($sql, $params);
}

/** Abre uma nota. 404 se não existe; 403 se o usuário não tem acesso (RNF-04). */
function nota_obter(int $id, int $uid): array
{
    $n = consultar_um(
        'SELECT n.id, n.dono_id, n.titulo, n.conteudo, n.criado_em, n.atualizado_em,
                u.nome AS dono_nome,
                ' . sql_permissao('u1') . ' AS permissao
           FROM notas n
           JOIN usuarios u ON u.id = n.dono_id
           LEFT JOIN compartilhamentos c ON c.nota_id = n.id AND c.usuario_id = :u2
          WHERE n.id = :n AND n.excluida = 0',
        ['u1' => $uid, 'u2' => $uid, 'n' => $id]
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

    return transacao(function () use ($uid, $titulo, $conteudo, $temas_ids) {
        executar(
            'INSERT INTO notas (dono_id, titulo, conteudo) VALUES (:d, :t, :c)',
            ['d' => $uid, 't' => $titulo, 'c' => $conteudo]
        );
        $id = ultimo_id();   // logo após o INSERT, antes de qualquer outro INSERT
        historico_registrar($id, $uid, 'criacao');   // RN-05
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

    transacao(function () use ($uid, $id, $titulo, $conteudo, $temas_ids, $perm) {
        // FOR UPDATE trava a linha até o fim da transação (edições simultâneas não se atropelam).
        $atual = consultar_um(
            'SELECT titulo, conteudo FROM notas WHERE id = :id AND excluida = 0 FOR UPDATE',
            ['id' => $id]
        );
        if (!$atual) {
            throw new ErroApp('Nota não encontrada.', 404);
        }
        // Comparação exata, caractere a caractere (trocar "aula" por "AULA" também é edição).
        // Se nada mudou, não grava nem cria linha de histórico.
        if ($atual['titulo'] !== $titulo || $atual['conteudo'] !== $conteudo) {
            historico_registrar($id, $uid, 'edicao', $atual['titulo'], $atual['conteudo']);   // RN-05
            executar('UPDATE notas SET titulo = :t, conteudo = :c WHERE id = :id',
                     ['t' => $titulo, 'c' => $conteudo, 'id' => $id]);
        }
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
    transacao(function () use ($uid, $id) {
        $atual = consultar_um(
            'SELECT titulo, conteudo FROM notas WHERE id = :id AND excluida = 0 FOR UPDATE',
            ['id' => $id]
        );
        if (!$atual) {
            throw new ErroApp('Nota não encontrada.', 404);
        }
        historico_registrar($id, $uid, 'exclusao', $atual['titulo'], $atual['conteudo']);   // RN-05
        executar('UPDATE notas SET excluida = 1, excluida_em = NOW() WHERE id = :id', ['id' => $id]);
    });
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
        // CAST(... AS UNSIGNED): o parâmetro chega como texto; aqui vira número, como a coluna.
        executar(
            'INSERT INTO notas_temas (nota_id, tema_id)
             SELECT CAST(:n AS UNSIGNED), id FROM temas WHERE id = :t AND usuario_id = :d',
            ['n' => $nota_id, 't' => $tema_id, 'd' => $dono_id]
        );
    }
}
