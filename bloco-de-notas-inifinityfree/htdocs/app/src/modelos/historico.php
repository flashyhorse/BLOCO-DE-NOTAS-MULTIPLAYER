<?php
/* =====================================================================
   MODELO: HISTÓRICO  (RF-05, RF-06, RN-05)
   (Antiga procedure MySQL: sp_restaurar_versao + consulta 10.7.)

   COMO O HISTÓRICO É GRAVADO?
   Não há triggers (hospedagens gratuitas e compartilhadas não os
   permitem). Quem grava é historico_registrar(), chamada pelas funções
   de notas.php DENTRO DA MESMA TRANSAÇÃO da alteração da nota:
   se uma falhar, a outra é desfeita junto.

   REGRA DE OURO (RN-05): este é o ÚNICO arquivo que escreve em
   historico_alteracoes, e só faz INSERT. Nada atualiza nem apaga
   linhas do histórico. Cada linha guarda a versão da nota ANTES da ação.

   ADAPTAR: nova ação de histórico -> veja schema.sql, guia item D.
   ===================================================================== */

/**
 * Grava uma linha no histórico. Chame SEMPRE dentro de transacao(),
 * junto com a alteração da nota.
 *
 * $acao: 'criacao' | 'edicao' | 'exclusao' | 'restauracao'
 * $titulo_anterior / $conteudo_anterior: versão da nota ANTES da ação
 * (null na criação, que não tem versão anterior).
 */
function historico_registrar(
    int $nota_id,
    int $uid,
    string $acao,
    ?string $titulo_anterior = null,
    ?string $conteudo_anterior = null
): void {
    executar(
        'INSERT INTO historico_alteracoes
                (nota_id, usuario_id, acao, titulo_anterior, conteudo_anterior)
         VALUES (:n, :u, :a, :t, :c)',
        ['n' => $nota_id, 'u' => $uid, 'a' => $acao, 't' => $titulo_anterior, 'c' => $conteudo_anterior]
    );
}

/** RF-05: histórico de uma nota (mais recente primeiro). Exige acesso à nota. */
function historico_listar(int $nota_id, int $uid): array
{
    nota_obter($nota_id, $uid);   // lança 403/404 se não pode ver

    // ADAPTAR: para ordem do mais antigo ao mais novo, troque DESC por ASC.
    return consultar(
        'SELECT h.id AS historico_id, u.nome AS autor, h.acao,
                h.titulo_anterior, h.conteudo_anterior, h.criado_em AS data_hora
           FROM historico_alteracoes h
           JOIN usuarios u ON u.id = h.usuario_id
          WHERE h.nota_id = :n
          ORDER BY h.criado_em DESC, h.id DESC',
        ['n' => $nota_id]
    );
}

/**
 * RF-06: devolve à nota o título/conteúdo guardados numa linha do
 * histórico (ou seja, o estado anterior àquela ação). Exige permissão de
 * edição. Gera uma nova linha 'restauracao' no histórico (nada é apagado).
 * Devolve o id da nota.
 */
function historico_restaurar(int $uid, int $historico_id): int
{
    // Só linhas que guardaram uma versão anterior (a de 'criacao' não guarda).
    $h = consultar_um(
        'SELECT nota_id, titulo_anterior, conteudo_anterior
           FROM historico_alteracoes
          WHERE id = :h AND conteudo_anterior IS NOT NULL',
        ['h' => $historico_id]
    );
    if (!$h) {
        throw new ErroApp('Versão não encontrada no histórico.', 404);
    }

    $nota_id = (int) $h['nota_id'];
    if (!in_array(nota_permissao($nota_id, $uid), ['dono', 'edicao'], true)) {
        throw new ErroApp('Sem permissão de edição para restaurar.', 403);   // RN-04
    }

    transacao(function () use ($uid, $nota_id, $h) {
        // FOR UPDATE trava a linha: duas pessoas restaurando/editando ao
        // mesmo tempo não embaralham o histórico.
        $atual = consultar_um(
            'SELECT titulo, conteudo FROM notas WHERE id = :n AND excluida = 0 FOR UPDATE',
            ['n' => $nota_id]
        );
        if (!$atual) {
            throw new ErroApp('Nota não encontrada.', 404);
        }
        // Se a nota já está igual à versão pedida, não há o que restaurar.
        if ($atual['titulo'] === $h['titulo_anterior'] && $atual['conteudo'] === $h['conteudo_anterior']) {
            return;
        }
        // Guarda o estado ATUAL (que vai ser substituído) e só então troca.
        historico_registrar($nota_id, $uid, 'restauracao', $atual['titulo'], $atual['conteudo']);
        executar(
            'UPDATE notas SET titulo = :t, conteudo = :c WHERE id = :n',
            ['t' => $h['titulo_anterior'], 'c' => $h['conteudo_anterior'], 'n' => $nota_id]
        );
    });

    return $nota_id;
}
