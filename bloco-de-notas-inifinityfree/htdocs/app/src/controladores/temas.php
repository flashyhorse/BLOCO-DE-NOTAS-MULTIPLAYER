<?php
/* =====================================================================
   CONTROLADOR: TEMAS  (RF-08)
   ===================================================================== */

function ctrl_temas_listar(): void
{
    renderizar('temas/lista', ['temas' => temas_do_usuario(uid())]);
}

function ctrl_temas_criar(): void
{
    tema_criar(uid(), post_str('nome'));
    flash('ok', 'Tema criado.');
    redirecionar('temas');
}

function ctrl_temas_renomear(): void
{
    tema_renomear(uid(), post_int('id'), post_str('nome'));
    flash('ok', 'Tema renomeado.');
    redirecionar('temas');
}

function ctrl_temas_excluir(): void
{
    tema_excluir(uid(), post_int('id'), isset($_POST['confirmar']));
    flash('ok', 'Tema excluído.');
    redirecionar('temas');
}
