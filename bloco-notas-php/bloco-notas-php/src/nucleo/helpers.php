<?php
/* =====================================================================
   FUNÇÕES AUXILIARES usadas em todo o projeto
   Agrupadas em: saída segura, entrada, navegação, mensagens, CSRF,
   login e telas.
   ===================================================================== */

/* ---------- Saída segura ---------- */

/** Escapa texto para HTML (evita XSS). Use SEMPRE ao imprimir dados: <?= e($x) ?> */
function e($valor): string
{
    return htmlspecialchars((string) $valor, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Formata um timestamp do banco como 31/12/2026 14:30 */
function fdata(?string $timestamp): string
{
    return $timestamp ? date('d/m/Y H:i', strtotime($timestamp)) : '';
}

/* ---------- Entrada (lê $_GET / $_POST com segurança) ---------- */

function get_str(string $campo): string
{
    $v = $_GET[$campo] ?? '';
    return is_string($v) ? trim($v) : '';
}

function get_int(string $campo): int
{
    $v = $_GET[$campo] ?? 0;
    return is_string($v) ? (int) $v : 0;
}

/** $aparar = false mantém espaços/quebras (usado no conteúdo da nota). */
function post_str(string $campo, bool $aparar = true): string
{
    $v = $_POST[$campo] ?? '';
    if (!is_string($v)) {
        return '';
    }
    return $aparar ? trim($v) : $v;
}

function post_int(string $campo): int
{
    $v = $_POST[$campo] ?? 0;
    return is_string($v) ? (int) $v : 0;
}

/** Lista de números vinda de checkboxes name="campo[]". */
function post_lista_int(string $campo): array
{
    $v = $_POST[$campo] ?? [];
    if (!is_array($v)) {
        return [];
    }
    return array_values(array_map('intval', array_filter($v, 'is_scalar')));
}

/* ---------- Navegação ---------- */

/**
 * Monta o endereço de uma rota: url('notas/ver', ['id' => 3])
 * -> /?r=notas/ver&id=3
 * As rotas existentes estão na tabela de public/index.php.
 */
function url(string $rota, array $params = []): string
{
    return '/?r=' . $rota . ($params ? '&' . http_build_query($params) : '');
}

function redirecionar(string $rota, array $params = []): void
{
    header('Location: ' . url($rota, $params));
    exit;
}

/**
 * Volta para a página de onde o usuário veio (usada após erro de formulário).
 * Só aceita referer do MESMO servidor; senão vai para $rota_padrao.
 */
function voltar(string $rota_padrao = 'notas'): void
{
    $p = parse_url($_SERVER['HTTP_REFERER'] ?? '');
    if ($p && isset($p['host'])) {
        $origem = $p['host'] . (isset($p['port']) ? ':' . $p['port'] : '');
        if ($origem === ($_SERVER['HTTP_HOST'] ?? '')) {
            $destino = '/' . ltrim($p['path'] ?? '/', '/') . (isset($p['query']) ? '?' . $p['query'] : '');
            header('Location: ' . $destino);
            exit;
        }
    }
    redirecionar($rota_padrao);
}

/* ---------- Mensagens (aparecem uma vez, na próxima tela) ---------- */

/** $tipo: 'ok' (verde) ou 'erro' (vermelho) */
function flash(string $tipo, string $mensagem): void
{
    $_SESSION['flash'][] = [$tipo, $mensagem];
}

function flashes(): array
{
    $lista = $_SESSION['flash'] ?? [];
    unset($_SESSION['flash']);
    return $lista;
}

/** Guarda o que o usuário digitou para reexibir no formulário após um erro. */
function guardar_antigo(array $dados): void
{
    unset($dados['_csrf']);
    foreach (array_keys($dados) as $k) {
        if (stripos((string) $k, 'senha') !== false) {
            unset($dados[$k]);   // nunca guarda senha
        }
    }
    $_SESSION['antigo'] = $dados;
}

/** Valor digitado antes do erro, ou $padrao. Uso: value="<?= e(antigo('titulo', $nota['titulo'] ?? '')) ?>" */
function antigo(string $campo, $padrao = '')
{
    return $GLOBALS['antigo'][$campo] ?? $padrao;
}

/* ---------- CSRF (impede que outro site envie formulários por você) ---------- */

function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

/** Coloque dentro de TODO <form method="post">: <?= csrf_campo() ?> */
function csrf_campo(): string
{
    return '<input type="hidden" name="_csrf" value="' . e(csrf_token()) . '">';
}

function csrf_validar(): void
{
    $enviado = $_POST['_csrf'] ?? '';
    if (!is_string($enviado) || !hash_equals($_SESSION['csrf'] ?? '', $enviado)) {
        throw new ErroApp('Formulário expirado ou inválido. Recarregue a página e tente de novo.', 403);
    }
}

/* ---------- Login / permissões de tela ---------- */

function usuario_logado(): ?array
{
    return $_SESSION['usuario'] ?? null;
}

function uid(): int
{
    return (int) ($_SESSION['usuario']['id'] ?? 0);
}

/**
 * Garante que há usuário logado. Também reconsulta o banco a cada
 * requisição: se o administrador bloqueou a conta (RF-10) ou mudou o
 * perfil, vale imediatamente.
 */
function exigir_login(): void
{
    if (!usuario_logado()) {
        redirecionar('entrar');
    }
    $u = consultar_um('SELECT nome, perfil, bloqueado FROM usuarios WHERE id = :id', ['id' => uid()]);
    if (!$u || $u['bloqueado']) {
        $_SESSION = [];
        session_regenerate_id(true);
        flash('erro', 'Sua conta está bloqueada ou não existe mais.');
        redirecionar('entrar');
    }
    $_SESSION['usuario']['nome']   = $u['nome'];
    $_SESSION['usuario']['perfil'] = $u['perfil'];
}

function exigir_perfil(string $perfil): void
{
    if ((usuario_logado()['perfil'] ?? '') !== $perfil) {
        throw new ErroApp('Acesso restrito.', 403);
    }
}

/* ---------- Telas ---------- */

/**
 * Desenha uma tela: renderizar('notas/lista', ['notas' => $notas]).
 *  - o arquivo src/visoes/<tela>.php recebe cada chave do array como variável
 *  - se a tela definir $titulo, ele aparece na aba do navegador
 *  - o resultado é colocado dentro de src/visoes/layout.php
 */
function renderizar(string $tela, array $dados = [], int $status = 200): void
{
    http_response_code($status);
    extract($dados, EXTR_SKIP);
    ob_start();
    require RAIZ . "/src/visoes/{$tela}.php";
    $conteudo = ob_get_clean();
    require RAIZ . '/src/visoes/layout.php';
}
