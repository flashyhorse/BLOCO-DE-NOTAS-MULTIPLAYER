<?php
/* =====================================================================
   MODELO: COMPARTILHAMENTOS  (RF-04, RN-03, RN-04)
   (Antigas procedures MySQL: sp_compartilhar_nota e
    sp_descompartilhar_nota.)
   Só o DONO da nota altera o compartilhamento.

   ADAPTAR: nova permissão (ex.: 'comentario') -> acrescente na lista
   PERMISSOES_COMPARTILHAMENTO e no CHECK do banco (schema.sql, item C).
   ===================================================================== */

const PERMISSOES_COMPARTILHAMENTO = ['leitura', 'edicao'];

/** Com quem a nota está compartilhada. */
function compartilhamentos_da_nota(int $nota_id): array
{
    return consultar(
        'SELECT c.usuario_id, u.nome, u.email, c.permissao
           FROM compartilhamentos c
           JOIN usuarios u ON u.id = c.usuario_id
          WHERE c.nota_id = :n
          ORDER BY u.nome',
        ['n' => $nota_id]
    );
}

/** Compartilha (ou muda a permissão de) uma nota, pelo e-mail do convidado. */
function compartilhar_nota(int $dono_id, int $nota_id, string $email_convidado, string $permissao): void
{
    if (!in_array($permissao, PERMISSOES_COMPARTILHAMENTO, true)) {
        throw new ErroApp('Permissão inválida.');
    }
    if (nota_permissao($nota_id, $dono_id) !== 'dono') {
        throw new ErroApp('Somente o dono altera o compartilhamento.', 403);
    }
    $convidado = consultar_um(
        'SELECT id FROM usuarios WHERE email = :e AND bloqueado = 0',
        ['e' => strtolower(trim($email_convidado))]
    );
    if (!$convidado) {
        throw new ErroApp('Usuário convidado não encontrado.');
    }
    if ((int) $convidado['id'] === $dono_id) {
        throw new ErroApp('O dono já tem acesso total à nota.');
    }

    // Se já existe compartilhamento (UNIQUE nota_id + usuario_id), só atualiza a
    // permissão (ON DUPLICATE KEY UPDATE = "upsert"). O valor vai duas vezes,
    // com nomes diferentes (:p e :p2), porque o MySQL não aceita o mesmo nome 2x.
    executar(
        'INSERT INTO compartilhamentos (nota_id, usuario_id, permissao)
         VALUES (:n, :u, :p)
         ON DUPLICATE KEY UPDATE permissao = :p2',
        ['n' => $nota_id, 'u' => $convidado['id'], 'p' => $permissao, 'p2' => $permissao]
    );
}

function descompartilhar_nota(int $dono_id, int $nota_id, int $usuario_id): void
{
    if (nota_permissao($nota_id, $dono_id) !== 'dono') {
        throw new ErroApp('Somente o dono altera o compartilhamento.', 403);
    }
    executar('DELETE FROM compartilhamentos WHERE nota_id = :n AND usuario_id = :u',
             ['n' => $nota_id, 'u' => $usuario_id]);
}
