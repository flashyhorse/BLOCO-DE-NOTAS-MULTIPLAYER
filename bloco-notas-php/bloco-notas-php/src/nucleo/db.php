<?php
/* =====================================================================
   ACESSO AO BANCO (PDO + PostgreSQL)
   REGRA DE OURO: nunca coloque dados do usuário dentro do texto do SQL.
   Use parâmetros nomeados (:nome) e passe os valores no array.
   Isso impede SQL Injection.

   Funções deste arquivo:
     db()                       conexão única (abre na primeira chamada)
     consultar($sql, $params)   várias linhas  -> array de arrays
     consultar_um(...)          uma linha      -> array ou null
     executar(...)              INSERT/UPDATE/DELETE -> nº de linhas afetadas
     transacao($uid, $fn)       executa $fn dentro de uma transação
                                informando ao banco QUEM está agindo
   ===================================================================== */

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $c = config('db');
        $dsn = "pgsql:host={$c['host']};port={$c['porta']};dbname={$c['nome']}";
        $pdo = new PDO($dsn, $c['usuario'], $c['senha'], [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION, // erro SQL vira exceção
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,       // linhas como ['coluna' => valor]
            PDO::ATTR_EMULATE_PREPARES   => false,                  // usa prepared statements reais
        ]);
    }
    return $pdo;
}

function consultar(string $sql, array $params = []): array
{
    $st = db()->prepare($sql);
    $st->execute($params);
    return $st->fetchAll();
}

function consultar_um(string $sql, array $params = []): ?array
{
    $st = db()->prepare($sql);
    $st->execute($params);
    $linha = $st->fetch();
    return $linha === false ? null : $linha;
}

function executar(string $sql, array $params = []): int
{
    $st = db()->prepare($sql);
    $st->execute($params);
    return $st->rowCount();
}

/**
 * Executa $fn dentro de uma transação (ou tudo dá certo, ou nada é gravado).
 *
 * Antes de rodar $fn, informa ao banco quem é o usuário (app.usuario_id)
 * e, opcionalmente, a ação do histórico (app.acao_historico). Os
 * triggers do schema.sql leem esses valores para gravar o histórico (RN-05).
 * O "true" em set_config() = valor vale só até o fim da transação.
 *
 * Retorna o que $fn retornar.
 */
function transacao(int $usuario_id, callable $fn, string $acao_historico = '')
{
    $pdo = db();
    $pdo->beginTransaction();
    try {
        consultar_um("SELECT set_config('app.usuario_id', :u, true)", ['u' => (string) $usuario_id]);
        consultar_um("SELECT set_config('app.acao_historico', :a, true)", ['a' => $acao_historico]);
        $resultado = $fn();
        $pdo->commit();
        return $resultado;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

/** true se a exceção do PDO foi "valor duplicado" (violação de UNIQUE). */
function erro_duplicado(PDOException $e): bool
{
    return $e->getCode() === '23505';
}
