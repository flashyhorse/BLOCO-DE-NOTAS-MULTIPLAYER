<?php
/* =====================================================================
   MODELO: USUÁRIOS  (RF-01, RF-02, RF-10, RN-01, RN-09, RN-10)
   Aqui ficam as consultas e regras de usuário/login.
   (Antigas procedures MySQL: sp_login_falho e sp_login_ok.)

   ADAPTAR: novo perfil -> acrescente na constante abaixo E no CHECK
   do banco (schema.sql, guia item B).
   ===================================================================== */

const PERFIS = ['aluno', 'instrutor', 'administrador'];

/** RF-01: cria usuário. Devolve o id novo. A senha é guardada como hash bcrypt (RNF-02). */
function usuario_criar(string $nome, string $email, string $senha, string $perfil = 'aluno'): int
{
    $nome  = trim($nome);
    $email = strtolower(trim($email));

    if ($nome === '' || mb_strlen($nome) > 100) {
        throw new ErroApp('Informe um nome com até 100 caracteres.');
    }
    if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 150) {
        throw new ErroApp('Informe um e-mail válido.');
    }
    $minimo = (int) config('senha_minima');
    if (mb_strlen($senha) < $minimo) {                                     // RN-09
        throw new ErroApp("A senha deve ter pelo menos {$minimo} caracteres.");
    }
    if (!in_array($perfil, PERFIS, true)) {
        throw new ErroApp('Perfil inválido.');
    }

    $hash = password_hash($senha, PASSWORD_DEFAULT);   // bcrypt; nunca guarde a senha pura

    try {
        executar(
            'INSERT INTO usuarios (nome, email, senha_hash, perfil)
             VALUES (:nome, :email, :hash, :perfil)',
            ['nome' => $nome, 'email' => $email, 'hash' => $hash, 'perfil' => $perfil]
        );
        $id = ultimo_id();
    } catch (PDOException $e) {
        if (erro_duplicado($e)) {                                          // RN-01
            throw new ErroApp('Já existe um usuário com este e-mail.');
        }
        throw $e;
    }
    return $id;
}

/**
 * RF-02 / RN-10: confere e-mail e senha.
 * Devolve ['id', 'nome', 'perfil'] se estiver tudo certo; senão lança ErroApp.
 * A mensagem para e-mail errado e senha errada é a MESMA de propósito
 * (não revela se o e-mail existe).
 */
function usuario_autenticar(string $email, string $senha): array
{
    // "email = :email" já ignora maiúsculas/minúsculas (collation utf8mb4_unicode_ci).
    $u = consultar_um(
        'SELECT id, nome, perfil, senha_hash, bloqueado,
                (bloqueado_ate IS NOT NULL AND bloqueado_ate > NOW()) AS bloqueio_temporario
           FROM usuarios
          WHERE email = :email',
        ['email' => strtolower(trim($email))]
    );

    if (!$u) {
        throw new ErroApp('E-mail ou senha inválidos.');
    }
    if ($u['bloqueado']) {                                                  // RF-10
        throw new ErroApp('Sua conta está bloqueada. Procure o administrador.');
    }
    if ($u['bloqueio_temporario']) {                                        // RN-10
        throw new ErroApp('Muitas tentativas incorretas. Aguarde alguns minutos e tente de novo.');
    }
    if (!password_verify($senha, $u['senha_hash'])) {
        usuario_registrar_falha_login((int) $u['id']);
        throw new ErroApp('E-mail ou senha inválidos.');
    }

    // Senha correta: zera o contador e remove bloqueio temporário.
    executar('UPDATE usuarios SET tentativas_login = 0, bloqueado_ate = NULL WHERE id = :id',
             ['id' => $u['id']]);

    return ['id' => (int) $u['id'], 'nome' => $u['nome'], 'perfil' => $u['perfil']];
}

/**
 * RN-10: soma uma tentativa errada; ao atingir o limite, bloqueia por X
 * minutos e zera o contador. Os números vêm de config/config.php.
 * ATENÇÃO À ORDEM: no UPDATE do MySQL as colunas são atribuídas da
 * esquerda para a direita. Por isso bloqueado_ate vem ANTES de
 * tentativas_login (assim ele ainda enxerga o valor antigo do contador).
 * Não inverta a ordem das duas linhas do SET.
 */
function usuario_registrar_falha_login(int $id): void
{
    $max = (int) config('login_max_tentativas');
    $min = (int) config('login_bloqueio_minutos');
    // $max e $min são inteiros vindos da configuração (não do usuário),
    // por isso podem ser escritos direto no SQL.
    executar(
        "UPDATE usuarios SET
            bloqueado_ate    = CASE WHEN tentativas_login + 1 >= {$max}
                                    THEN NOW() + INTERVAL {$min} MINUTE
                                    ELSE bloqueado_ate END,
            tentativas_login = CASE WHEN tentativas_login + 1 >= {$max}
                                    THEN 0
                                    ELSE tentativas_login + 1 END
          WHERE id = :id",
        ['id' => $id]
    );
}

/* ---------- Administração (RF-10) ---------- */

function usuarios_listar(): array
{
    return consultar(
        'SELECT id, nome, email, perfil, bloqueado,
                (bloqueado_ate IS NOT NULL AND bloqueado_ate > NOW()) AS bloqueio_temporario
           FROM usuarios
          ORDER BY nome'
    );
}

function usuario_definir_bloqueio(int $admin_id, int $id, bool $bloquear): void
{
    if ($bloquear && $admin_id === $id) {
        throw new ErroApp('Você não pode bloquear a própria conta.');
    }
    if ($bloquear) {
        $n = executar('UPDATE usuarios SET bloqueado = TRUE WHERE id = :id', ['id' => $id]);
    } else {
        // Desbloquear também limpa tentativas e bloqueio temporário.
        $n = executar('UPDATE usuarios
                          SET bloqueado = FALSE, tentativas_login = 0, bloqueado_ate = NULL
                        WHERE id = :id', ['id' => $id]);
    }
    if ($n === 0) {
        throw new ErroApp('Usuário não encontrado.', 404);
    }
}

function usuario_definir_perfil(int $admin_id, int $id, string $perfil): void
{
    if (!in_array($perfil, PERFIS, true)) {
        throw new ErroApp('Perfil inválido.');
    }
    if ($admin_id === $id && $perfil !== 'administrador') {
        throw new ErroApp('Você não pode remover o seu próprio perfil de administrador.');
    }
    $n = executar('UPDATE usuarios SET perfil = :perfil WHERE id = :id', ['perfil' => $perfil, 'id' => $id]);
    if ($n === 0) {
        throw new ErroApp('Usuário não encontrado.', 404);
    }
}
