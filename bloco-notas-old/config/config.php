<?php
/* =====================================================================
   CONFIGURAÇÃO DA APLICAÇÃO
   Tudo que você pode querer trocar sem mexer no código fica aqui.
   Leitura no código: config('db.host'), config('senha_minima') ...
   As credenciais do banco podem vir de variáveis de ambiente
   (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS); se não existirem,
   valem os valores padrão abaixo (MySQL local: root, sem senha).
   ===================================================================== */
$db_senha = getenv('DB_PASS');   // false se não existir ('' é uma senha válida)

return [
    'app_nome' => 'Bloco de Notas Compartilhado',

    // true  = mostra detalhes dos erros na tela (use só em desenvolvimento)
    // false = mostra mensagem genérica
    'debug' => true,

    // Conexão com o MySQL 8.0+ (ou MariaDB 10.4+)
    'db' => [
        'host'    => getenv('DB_HOST') ?: '127.0.0.1',   // 127.0.0.1 força TCP (evita problema de socket)
        'porta'   => getenv('DB_PORT') ?: '3306',
        'nome'    => getenv('DB_NAME') ?: 'bloco_notas',
        'usuario' => getenv('DB_USER') ?: 'root',
        'senha'   => $db_senha === false ? '' : $db_senha,
    ],

    // RN-09: tamanho mínimo da senha (valor assumido; confirmar com o cliente)
    'senha_minima' => 8,

    // RN-10: após N senhas erradas seguidas, bloqueia por X minutos
    'login_max_tentativas'   => 5,
    'login_bloqueio_minutos' => 15,
];
