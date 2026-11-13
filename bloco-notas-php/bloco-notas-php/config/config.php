<?php
/* =====================================================================
   CONFIGURAÇÃO DA APLICAÇÃO
   Tudo que você pode querer trocar sem mexer no código fica aqui.
   Leitura no código: config('db.host'), config('senha_minima') ...
   As credenciais do banco podem vir de variáveis de ambiente
   (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS); se não existirem,
   valem os valores depois do "?:".
   ===================================================================== */
return [
    'app_nome' => 'Bloco de Notas Compartilhado',

    // true  = mostra detalhes dos erros na tela (use só em desenvolvimento)
    // false = mostra mensagem genérica
    'debug' => true,

    // Conexão com o PostgreSQL
    'db' => [
        'host'    => getenv('DB_HOST') ?: 'localhost',
        'porta'   => getenv('DB_PORT') ?: '5432',
        'nome'    => getenv('DB_NAME') ?: 'bloco_notas',
        'usuario' => getenv('DB_USER') ?: 'postgres',
        'senha'   => getenv('DB_PASS') ?: 'postgres',
    ],

    // RN-09: tamanho mínimo da senha (valor assumido; confirmar com o cliente)
    'senha_minima' => 8,

    // RN-10: após N senhas erradas seguidas, bloqueia por X minutos
    'login_max_tentativas'   => 5,
    'login_bloqueio_minutos' => 15,
];
