<?php
/* =====================================================================
   CONTROLADOR: NOTAS  (RF-03, RF-05, RF-06, RF-08, RF-09)
   Cada função abaixo é uma "página" ou uma "ação" (POST).
   As regras de negócio ficam em src/modelos/notas.php.
   ===================================================================== */

/** Lista + busca + filtro por tema. */
function ctrl_notas_listar(): void
{
    $busca   = get_str('busca');
    $tema_id = get_int('tema') ?: null;

    renderizar('notas/lista', [
        'notas'   => notas_listar(uid(), $busca, $tema_id),
        'temas'   => temas_do_usuario(uid()),
        'busca'   => $busca,
        'tema_id' => $tema_id,
    ]);
}

/** Visualiza uma nota (com temas e, se for dono, painel de compartilhamento). */
function ctrl_notas_ver(): void
{
    $nota = nota_obter(get_int('id'), uid());

    renderizar('notas/ver', [
        'nota'             => $nota,
        'temas_da_nota'    => nota_temas($nota['id']),
        'compartilhados'   => $nota['permissao'] === 'dono' ? compartilhamentos_da_nota($nota['id']) : [],
    ]);
}

/** Formulário de nova nota. */
function ctrl_notas_nova(): void
{
    renderizar('notas/form', [
        'modo'      => 'criar',
        'nota'      => null,
        'temas'     => temas_do_usuario(uid()),
        'marcados'  => [],
        'e_dono'    => true,
    ]);
}

function ctrl_notas_criar(): void
{
    $id = nota_criar(uid(), post_str('titulo'), post_str('conteudo', false), post_lista_int('temas'));
    flash('ok', 'Nota criada.');
    redirecionar('notas/ver', ['id' => $id]);
}

/** Formulário de edição (dono ou permissão 'edicao'). */
function ctrl_notas_editar(): void
{
    $nota = nota_obter(get_int('id'), uid());
    if ($nota['permissao'] === 'leitura') {
        throw new ErroApp('Você tem apenas permissão de leitura nesta nota.', 403);
    }
    $e_dono = $nota['permissao'] === 'dono';

    renderizar('notas/form', [
        'modo'     => 'editar',
        'nota'     => $nota,
        'temas'    => $e_dono ? temas_do_usuario(uid()) : [],
        'marcados' => nota_temas_ids($nota['id']),
        'e_dono'   => $e_dono,
    ]);
}

function ctrl_notas_atualizar(): void
{
    $id = post_int('id');
    // O formulário do dono envia "temas_enviados"; sem ele, não mexemos nos temas.
    $temas = isset($_POST['temas_enviados']) ? post_lista_int('temas') : null;

    nota_editar(uid(), $id, post_str('titulo'), post_str('conteudo', false), $temas);
    flash('ok', 'Nota atualizada.');
    redirecionar('notas/ver', ['id' => $id]);
}

function ctrl_notas_excluir(): void
{
    nota_excluir(uid(), post_int('id'));
    flash('ok', 'Nota excluída. (Ela continua guardada no histórico.)');
    redirecionar('notas');
}

/** RF-05: histórico de alterações. */
function ctrl_notas_historico(): void
{
    $nota = nota_obter(get_int('id'), uid());

    renderizar('notas/historico', [
        'nota'        => $nota,
        'historico'   => historico_listar($nota['id'], uid()),
        'pode_editar' => in_array($nota['permissao'], ['dono', 'edicao'], true),
    ]);
}

/** RF-06: restaurar uma versão. */
function ctrl_notas_restaurar(): void
{
    $nota_id = historico_restaurar(uid(), post_int('historico_id'));
    flash('ok', 'Versão restaurada.');
    redirecionar('notas/ver', ['id' => $nota_id]);
}
