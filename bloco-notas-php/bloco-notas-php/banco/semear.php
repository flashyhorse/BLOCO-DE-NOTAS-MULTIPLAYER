<?php
/* =====================================================================
   DADOS DE EXEMPLO (somente desenvolvimento / testes)
   Uso (na pasta do projeto):   php banco/semear.php

   Cria 3 usuários (senha de todos: senha1234), temas, notas,
   compartilhamentos e uma edição, usando as MESMAS funções da
   aplicação - então também serve de teste rápido do código.
   Não execute duas vezes (e-mails são únicos).
   ===================================================================== */

require __DIR__ . '/../src/nucleo/bootstrap.php';

try {
    $senha = 'senha1234';

    // Os hashes bcrypt são gerados por usuario_criar() (RNF-02).
    usuario_criar('Administrador', 'admin@senai.exemplo', $senha, 'administrador');
    $maria = usuario_criar('Profa. Maria', 'maria@senai.exemplo', $senha, 'instrutor');
    $joao  = usuario_criar('João Aluno',   'joao@senai.exemplo',  $senha, 'aluno');

    // Temas da Profa. Maria
    $bd = tema_criar($maria, 'Banco de Dados');
    $pi = tema_criar($maria, 'Projeto Integrador');

    // Notas (o histórico de criação é gravado pelo trigger)
    $n1 = nota_criar($maria, 'Aula 01 - Modelagem',  'Entidades, atributos e relacionamentos.', [$bd]);
    $n2 = nota_criar($maria, 'Aula 02 - SQL básico', 'SELECT, INSERT, UPDATE e DELETE.', [$bd, $pi]);

    // João pode EDITAR a nota 1 e só LER a nota 2
    compartilhar_nota($maria, $n1, 'joao@senai.exemplo', 'edicao');
    compartilhar_nota($maria, $n2, 'joao@senai.exemplo', 'leitura');

    // João edita a nota 1 (gera histórico com autor = João)
    nota_editar($joao, $n1, 'Aula 01 - Modelagem',
                'Entidades, atributos, relacionamentos e cardinalidade.');

    echo "Dados de exemplo criados.\n";
    echo "Logins: admin@senai.exemplo / maria@senai.exemplo / joao@senai.exemplo  (senha: {$senha})\n";

    // TESTE DA RN-04 (deve dar erro, pois João só tem leitura na nota 2):
    // nota_editar($joao, $n2, 'Tentativa', 'não deve funcionar');

} catch (ErroApp $e) {
    echo 'Não foi possível criar os dados: ' . $e->getMessage() . "\n";
    exit(1);
} catch (PDOException $e) {
    echo 'Erro de banco: ' . $e->getMessage() . "\n";
    echo "Confira config/config.php e se o schema.sql já foi executado.\n";
    exit(1);
}
