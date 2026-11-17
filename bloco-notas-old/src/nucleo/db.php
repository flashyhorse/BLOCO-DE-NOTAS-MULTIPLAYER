<?php
/* =====================================================================
   ACESSO AO BANCO (PDO + MySQL)
   REGRA DE OURO: nunca coloque dados do usuário dentro do texto do SQL.
   Use parâmetros nomeados (:nome) e passe os valores no array.
   Isso impede SQL Injection.

   Funções deste arquivo:
     db()                       conexão única (abre na primeira chamada)
     consultar($sql, $params)   várias linhas  -> array de arrays
     consultar_um(...)          uma linha      -> array ou null
     executar(...)              INSERT/UPDATE/DELETE -> nº de linhas afetadas
     ultimo_id()                id gerado pelo último INSERT (AUTO_INCREMENT)
     transacao($uid, $fn)       executa $fn dentro de uma transação
                                informando ao banco QUEM está agindo

   ATENÇÃO (prepared statements reais no MySQL): o mesmo parâmetro
   nomeado NÃO pode aparecer duas vezes na mesma consulta. Se precisar
   do mesmo valor duas vezes, use dois nomes (:b1 e :b2) e passe o valor
   duas vezes.
   ===================================================================== */

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $c = config('db');
        $dsn = "mysql:host={$c['host']};port={$c['porta']};dbname={$c['nome']};charset=utf8mb4";
        $pdo = new PDO($dsn, $c['usuario'], $c['senha'], [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION, // erro SQL vira exceção
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,       // linhas como ['coluna' => valor]
            PDO::ATTR_EMULATE_PREPARES   => false,                  // usa prepared statements reais
        ]);
        // Acentos corretos e o MESMO fuso do PHP: assim NOW() do banco e as
        // datas exibidas pelo PHP (fdata) concordam, mesmo que o servidor
        // MySQL esteja em UTC. date('P') devolve o deslocamento, ex.: -03:00.
        $pdo->exec("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci");
        $pdo->exec("SET time_zone = '" . date('P') . "'");
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

/** Id gerado (AUTO_INCREMENT) pelo último INSERT desta conexão. Chame logo após o INSERT. */
function ultimo_id(): int
{
    return (int) db()->lastInsertId();
}

/**
 * Executa $fn dentro de uma transação (ou tudo dá certo, ou nada é gravado).
 *
 * Antes de rodar $fn, informa ao banco quem é o usuário (@usuario_id_atual)
 * e, opcionalmente, a ação do histórico (@acao_historico). Os triggers do
 * schema.sql leem essas variáveis de sessão para gravar o histórico (RN-05).
 *
 * Diferente do PostgreSQL, a variável de sessão do MySQL NÃO some sozinha
 * no fim da transação; por isso ela é zerada no "finally". Assim, uma
 * alteração em "notas" fora de transacao() continua sendo recusada.
 *
 * Retorna o que $fn retornar.
 */
function transacao(int $usuario_id, callable $fn, string $acao_historico = '')
{
    $pdo = db();
    $pdo->beginTransaction();
    try {
        executar('SET @usuario_id_atual = :u', ['u' => $usuario_id]);
        executar("SET @acao_historico = NULLIF(:a, '')", ['a' => $acao_historico]);
        $resultado = $fn();
        $pdo->commit();
        return $resultado;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    } finally {
        try {
            $pdo->exec('SET @usuario_id_atual = NULL, @acao_historico = NULL');
        } catch (Throwable $ignorado) {
            // conexão já caiu; não esconde o erro original
        }
    }
}

/**
 * true se a exceção do PDO foi "valor duplicado" (violação de UNIQUE).
 * MySQL: SQLSTATE 23000 + código de driver 1062 (ER_DUP_ENTRY). O 23000
 * sozinho também serve para outras violações (ex.: chave estrangeira),
 * por isso confere o 1062.
 */
function erro_duplicado(PDOException $e): bool
{
    return $e->getCode() === '23000' && (int) ($e->errorInfo[1] ?? 0) === 1062;
}
