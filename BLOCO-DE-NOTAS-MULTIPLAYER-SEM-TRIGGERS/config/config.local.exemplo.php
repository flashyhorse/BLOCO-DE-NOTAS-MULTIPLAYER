<?php
/* =====================================================================
   CONFIGURAÇÃO DE PRODUÇÃO (hospedagem)
   1) Copie este arquivo para  config/config.local.php
   2) Preencha os dados do banco que o PAINEL da hospedagem mostrou
   3) Mantenha 'debug' => false

   Só coloque aqui o que muda; o resto vem de config.php.
   Nunca envie o config.local.php para o Git (ele tem a senha do banco).

   ONDE ACHAR OS DADOS DO BANCO
   - Hostinger:    hPanel > Bancos de dados > Gerenciamento
                   host: normalmente "localhost"
                   nome/usuário: com prefixo, ex.: u123456789_bloco
   - InfinityFree: Painel > MySQL Databases
                   host: ex.: sql123.infinityfree.com (aparece no painel)
                   nome/usuário: com prefixo, ex.: if0_12345678_bloco
                   senha: a que você definiu para a conta/painel
   ===================================================================== */
return [
    'debug' => false,

    'db' => [
        'host'    => 'localhost',
        'porta'   => '3306',
        'nome'    => 'COLOQUE_O_NOME_DO_BANCO',
        'usuario' => 'COLOQUE_O_USUARIO',
        'senha'   => 'COLOQUE_A_SENHA',
    ],
];
