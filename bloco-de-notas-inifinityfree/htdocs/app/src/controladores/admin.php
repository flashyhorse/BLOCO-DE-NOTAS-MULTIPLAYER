<?php
/* =====================================================================
   CONTROLADOR: ADMINISTRAÇÃO  (RF-10)
   Só o perfil 'administrador' chega aqui (a tabela de rotas exige).
   ===================================================================== */

function ctrl_admin_usuarios(): void
{
    renderizar('admin/usuarios', ['usuarios' => usuarios_listar()]);
}

/** Uma única ação POST para os 3 botões da linha: bloquear, desbloquear, mudar perfil. */
function ctrl_admin_usuarios_atualizar(): void
{
    $id   = post_int('usuario_id');
    $acao = post_str('acao');

    if ($acao === 'bloquear') {
        usuario_definir_bloqueio(uid(), $id, true);
        flash('ok', 'Usuário bloqueado.');
    } elseif ($acao === 'desbloquear') {
        usuario_definir_bloqueio(uid(), $id, false);
        flash('ok', 'Usuário desbloqueado.');
    } elseif ($acao === 'perfil') {
        usuario_definir_perfil(uid(), $id, post_str('perfil'));
        flash('ok', 'Perfil alterado.');
    } else {
        throw new ErroApp('Ação desconhecida.');
    }
    redirecionar('admin/usuarios');
}
