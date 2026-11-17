<?php
/* =====================================================================
   CONTROLADOR: AUTENTICAÇÃO  (RF-01, RF-02)
   Controlador = recebe a requisição, chama o MODELO e escolhe a TELA.
   Convenção de nomes: ctrl_<arquivo>_<ação>  (ligada na tabela de
   rotas de public/index.php).
   ===================================================================== */

function ctrl_auth_entrar(): void
{
    if (usuario_logado()) {
        redirecionar('notas');
    }
    renderizar('auth/entrar');
}

function ctrl_auth_entrar_enviar(): void
{
    $u = usuario_autenticar(post_str('email'), post_str('senha', false));

    session_regenerate_id(true);          // novo id de sessão após login (evita fixação de sessão)
    $_SESSION['usuario'] = $u;
    redirecionar('notas');
}

function ctrl_auth_registrar(): void
{
    if (usuario_logado()) {
        redirecionar('notas');
    }
    renderizar('auth/registrar');
}

function ctrl_auth_registrar_enviar(): void
{
    $senha = post_str('senha', false);
    if ($senha !== post_str('senha2', false)) {
        throw new ErroApp('A confirmação da senha não confere.');
    }
    // Quem se cadastra sozinho sempre começa como 'aluno'.
    // O administrador muda o perfil depois (tela Administração).
    usuario_criar(post_str('nome'), post_str('email'), $senha, 'aluno');

    flash('ok', 'Cadastro realizado! Entre com seu e-mail e senha.');
    redirecionar('entrar');
}

function ctrl_auth_sair(): void
{
    $_SESSION = [];
    session_regenerate_id(true);
    flash('ok', 'Você saiu do sistema.');
    redirecionar('entrar');
}
