<?php
/* =====================================================================
   MODELO: HISTÓRICO  (RF-05, RF-06, RN-05)
   (Antiga procedure MySQL: sp_restaurar_versao + consulta 10.7.)

   O histórico é GRAVADO pelos triggers do banco; aqui só LEMOS e
   RESTAURAMOS. Cada linha guarda a versão da nota ANTES da ação.
   ===================================================================== */

/** RF-05: histórico de uma nota (mais recente primeiro). Exige acesso à nota. */
function historico_listar(int $nota_id, int $uid): array
{
    nota_obter($nota_id, $uid);   // lança 403/404 se não pode ver

    // ADAPTAR: para ordem do mais antigo ao mais novo, troque DESC por ASC.
    return consultar(
        'SELECT historico_id, autor, acao, titulo_anterior, conteudo_anterior, data_hora
           FROM vw_historico_detalhado
          WHERE nota_id = :n
          ORDER BY data_hora DESC, historico_id DESC',
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

    // O 3º parâmetro faz o trigger registrar a ação como 'restauracao'.
    transacao($uid, fn() => executar(
        'UPDATE notas SET titulo = :t, conteudo = :c WHERE id = :n',
        ['t' => $h['titulo_anterior'], 'c' => $h['conteudo_anterior'], 'n' => $nota_id]
    ), 'restauracao');

    return $nota_id;
}
