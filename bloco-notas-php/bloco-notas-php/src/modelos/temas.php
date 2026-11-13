<?php
/* =====================================================================
   MODELO: TEMAS  (RF-08, RN-07, RN-08)
   (Antiga procedure MySQL: sp_excluir_tema.)
   ===================================================================== */

/** Temas do usuário com a quantidade de notas ativas (view vw_temas_resumo). */
function temas_do_usuario(int $uid): array
{
    return consultar(
        'SELECT tema_id AS id, tema AS nome, total_notas
           FROM vw_temas_resumo
          WHERE usuario_id = :u
          ORDER BY tema',
        ['u' => $uid]
    );
}

function validar_nome_tema(string $nome): void
{
    if ($nome === '' || mb_strlen($nome) > 80) {
        throw new ErroApp('Informe um nome de tema com até 80 caracteres.');
    }
}

/** Cria tema. RN-08: o nome não pode repetir para o mesmo usuário. Devolve o id. */
function tema_criar(int $uid, string $nome): int
{
    validar_nome_tema($nome);
    try {
        $r = consultar_um('INSERT INTO temas (usuario_id, nome) VALUES (:u, :n) RETURNING id',
                          ['u' => $uid, 'n' => $nome]);
    } catch (PDOException $e) {
        if (erro_duplicado($e)) {
            throw new ErroApp('Você já tem um tema com este nome.');
        }
        throw $e;
    }
    return (int) $r['id'];
}

function tema_renomear(int $uid, int $id, string $nome): void
{
    validar_nome_tema($nome);
    try {
        $n = executar('UPDATE temas SET nome = :n WHERE id = :id AND usuario_id = :u',
                      ['n' => $nome, 'id' => $id, 'u' => $uid]);
    } catch (PDOException $e) {
        if (erro_duplicado($e)) {
            throw new ErroApp('Você já tem um tema com este nome.');
        }
        throw $e;
    }
    if ($n === 0) {
        throw new ErroApp('Tema não encontrado.', 404);
    }
}

/**
 * RN-07: se o tema tem notas, só exclui com $confirmar = true.
 * As notas NÃO são apagadas; apenas perdem a ligação com o tema.
 */
function tema_excluir(int $uid, int $id, bool $confirmar): void
{
    $t = consultar_um('SELECT total_notas FROM vw_temas_resumo WHERE tema_id = :t AND usuario_id = :u',
                      ['t' => $id, 'u' => $uid]);
    if (!$t) {
        throw new ErroApp('Tema não encontrado.', 404);
    }
    if ((int) $t['total_notas'] > 0 && !$confirmar) {
        throw new ErroApp('Este tema possui notas vinculadas. Marque a confirmação para excluir.');
    }
    transacao($uid, function () use ($id) {
        executar('DELETE FROM notas_temas WHERE tema_id = :t', ['t' => $id]);   // solta as notas
        executar('DELETE FROM temas WHERE id = :t', ['t' => $id]);
    });
}
