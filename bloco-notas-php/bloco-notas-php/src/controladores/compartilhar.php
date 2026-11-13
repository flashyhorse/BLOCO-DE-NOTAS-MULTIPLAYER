<?php
/* =====================================================================
   CONTROLADOR: COMPARTILHAMENTO  (RF-04)
   Só o dono da nota pode usar estas ações (o modelo confere).
   ===================================================================== */

function ctrl_compartilhar_salvar(): void
{
    $nota_id = post_int('nota_id');
    compartilhar_nota(uid(), $nota_id, post_str('email'), post_str('permissao'));
    flash('ok', 'Compartilhamento salvo.');
    redirecionar('notas/ver', ['id' => $nota_id]);
}

function ctrl_compartilhar_remover(): void
{
    $nota_id = post_int('nota_id');
    descompartilhar_nota(uid(), $nota_id, post_int('usuario_id'));
    flash('ok', 'Compartilhamento removido.');
    redirecionar('notas/ver', ['id' => $nota_id]);
}
