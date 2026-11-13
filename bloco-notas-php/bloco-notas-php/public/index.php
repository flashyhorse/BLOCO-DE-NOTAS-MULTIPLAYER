<?php
/* =====================================================================
   PORTA DE ENTRADA (front controller)
   Todo acesso passa por aqui:  http://localhost:8000/?r=<rota>

   Para iniciar o servidor (na pasta do projeto):
        php -S localhost:8000 -t public

   COMO ADICIONAR UMA PÁGINA NOVA (3 passos)
     1) escreva a função ctrl_<controlador>_<acao>() em src/controladores/
     2) crie a tela em src/visoes/ (se for uma página)
     3) acrescente UMA linha na tabela $rotas abaixo
   ===================================================================== */

require __DIR__ . '/../src/nucleo/bootstrap.php';

/*
 * TABELA DE ROTAS
 *   'rota'  => [método, controlador, ação, exige_login, perfil_exigido]
 *
 *   método          GET (mostrar página) ou POST (executar ação)
 *   controlador     arquivo em src/controladores/ (sem .php)
 *   ação            a função chamada é ctrl_<controlador>_<ação>
 *   exige_login     true = só usuário logado
 *   perfil_exigido  null = qualquer perfil, ou 'administrador'
 */
$rotas = [
    // ---- Login e cadastro ----
    'entrar'                => ['GET',  'auth', 'entrar',            false, null],
    'entrar/enviar'         => ['POST', 'auth', 'entrar_enviar',     false, null],
    'registrar'             => ['GET',  'auth', 'registrar',         false, null],
    'registrar/enviar'      => ['POST', 'auth', 'registrar_enviar',  false, null],
    'sair'                  => ['POST', 'auth', 'sair',              true,  null],

    // ---- Notas (CRUD) ----
    'notas'                 => ['GET',  'notas', 'listar',     true, null],   // R  - listar/buscar
    'notas/ver'             => ['GET',  'notas', 'ver',        true, null],   // R  - abrir
    'notas/nova'            => ['GET',  'notas', 'nova',       true, null],   // C  - formulário
    'notas/criar'           => ['POST', 'notas', 'criar',      true, null],   // C  - gravar
    'notas/editar'          => ['GET',  'notas', 'editar',     true, null],   // U  - formulário
    'notas/atualizar'       => ['POST', 'notas', 'atualizar',  true, null],   // U  - gravar
    'notas/excluir'         => ['POST', 'notas', 'excluir',    true, null],   // D  - exclusão lógica
    'notas/historico'       => ['GET',  'notas', 'historico',  true, null],
    'notas/restaurar'       => ['POST', 'notas', 'restaurar',  true, null],

    // ---- Compartilhamento ----
    'compartilhar/salvar'   => ['POST', 'compartilhar', 'salvar',  true, null],
    'compartilhar/remover'  => ['POST', 'compartilhar', 'remover', true, null],

    // ---- Temas (CRUD) ----
    'temas'                 => ['GET',  'temas', 'listar',    true, null],
    'temas/criar'           => ['POST', 'temas', 'criar',     true, null],
    'temas/renomear'        => ['POST', 'temas', 'renomear',  true, null],
    'temas/excluir'         => ['POST', 'temas', 'excluir',   true, null],

    // ---- Administração (só administrador) ----
    'admin/usuarios'            => ['GET',  'admin', 'usuarios',            true, 'administrador'],
    'admin/usuarios/atualizar'  => ['POST', 'admin', 'usuarios_atualizar',  true, 'administrador'],
];

$rota   = $_GET['r'] ?? 'notas';           // página inicial: lista de notas
$metodo = $_SERVER['REQUEST_METHOD'];

try {
    if (!is_string($rota) || !isset($rotas[$rota])) {
        throw new ErroApp('Página não encontrada.', 404);
    }
    [$metodo_ok, $controlador, $acao, $exige_login, $perfil] = $rotas[$rota];

    if ($metodo !== $metodo_ok) {
        throw new ErroApp('Método não permitido.', 405);
    }
    if ($metodo === 'POST') {
        csrf_validar();                    // todo POST precisa do token do formulário
    }
    if ($exige_login) {
        exigir_login();
    }
    if ($perfil !== null) {
        exigir_perfil($perfil);
    }

    // $controlador e $acao vêm da tabela acima (nunca do usuário): seguro.
    require_once RAIZ . "/src/controladores/{$controlador}.php";
    call_user_func("ctrl_{$controlador}_{$acao}");

} catch (ErroApp $e) {
    if ($e->status === 422) {
        // Erro de preenchimento: mostra a mensagem e volta ao formulário
        // com o que o usuário já tinha digitado.
        guardar_antigo($_POST);
        flash('erro', $e->getMessage());
        voltar();
    }
    // 403, 404, 405...: tela de erro
    renderizar('erro', ['codigo' => $e->status, 'mensagem' => $e->getMessage()], $e->status);

} catch (PDOException $e) {
    // Erro inesperado de banco (conexão, SQL, regra violada por trigger...)
    $detalhe = config('debug') ? $e->getMessage() : 'Erro ao acessar o banco de dados.';
    renderizar('erro', ['codigo' => 500, 'mensagem' => $detalhe], 500);
}
