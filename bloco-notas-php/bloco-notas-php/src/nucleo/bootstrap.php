<?php
/* =====================================================================
   BOOTSTRAP - roda no início de TODA requisição (e do semear.php)
   O que faz, em ordem:
     1. carrega a configuração
     2. define a classe de erro da aplicação (ErroApp)
     3. carrega helpers, banco e modelos
     4. inicia a sessão (login) - só quando é navegador, não no terminal
   Requer PHP 8.0+ com as extensões pdo_mysql e mbstring habilitadas.
   ===================================================================== */

define('RAIZ', dirname(__DIR__, 2));   // pasta raiz do projeto

$GLOBALS['config'] = require RAIZ . '/config/config.php';

/** Lê uma configuração. Aceita caminho com ponto: config('db.host'). */
function config(string $chave, $padrao = null)
{
    $valor = $GLOBALS['config'];
    foreach (explode('.', $chave) as $parte) {
        if (!is_array($valor) || !array_key_exists($parte, $valor)) {
            return $padrao;
        }
        $valor = $valor[$parte];
    }
    return $valor;
}

error_reporting(E_ALL);
ini_set('display_errors', config('debug') ? '1' : '0');
date_default_timezone_set('America/Sao_Paulo');

/**
 * ErroApp = erro "esperado" (regra de negócio violada, acesso negado...).
 * O segundo parâmetro é o código HTTP:
 *   422 -> erro de preenchimento: volta ao formulário com a mensagem
 *   403 -> sem permissão      404 -> não encontrado
 * Quem trata é o roteador (public/index.php).
 */
class ErroApp extends Exception
{
    public int $status;

    public function __construct(string $mensagem, int $status = 422)
    {
        parent::__construct($mensagem);
        $this->status = $status;
    }
}

require RAIZ . '/src/nucleo/helpers.php';
require RAIZ . '/src/nucleo/db.php';
foreach (['usuarios', 'notas', 'temas', 'compartilhamentos', 'historico'] as $modelo) {
    require RAIZ . "/src/modelos/{$modelo}.php";
}

if (PHP_SAPI !== 'cli') {
    session_start([
        'cookie_httponly' => true,     // JavaScript não lê o cookie de sessão
        'cookie_samesite' => 'Lax',    // ajuda contra CSRF
    ]);
    // Dados digitados que voltam ao formulário após um erro (ver antigo()).
    // Ficam disponíveis só nesta requisição.
    $GLOBALS['antigo'] = $_SESSION['antigo'] ?? [];
    unset($_SESSION['antigo']);
}
