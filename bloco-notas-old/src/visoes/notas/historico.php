<?php
$titulo = 'Histórico – ' . $nota['titulo'];
// Rótulos legíveis para o valor da coluna "acao". Nova ação? Acrescente aqui.
$rotulos = ['criacao' => 'Criação', 'edicao' => 'Edição', 'exclusao' => 'Exclusão', 'restauracao' => 'Restauração'];
?>
<div class="barra">
  <h1>Histórico: <?= e($nota['titulo']) ?></h1>
  <a class="botao secundario" href="<?= e(url('notas/ver', ['id' => $nota['id']])) ?>">Voltar à nota</a>
</div>
<p class="nota">Cada linha mostra quem fez a ação e como a nota estava <strong>antes</strong> dela.
  Restaurar volta a nota àquele estado (e fica registrado como nova ação; nada é apagado).</p>

<div class="tabela-rolagem">
<table>
  <thead><tr><th>Quando</th><th>Quem</th><th>Ação</th><th>Versão anterior</th></tr></thead>
  <tbody>
  <?php foreach ($historico as $h): ?>
    <tr>
      <td><?= e(fdata($h['data_hora'])) ?></td>
      <td><?= e($h['autor']) ?></td>
      <td><?= e($rotulos[$h['acao']] ?? $h['acao']) ?></td>
      <td>
        <?php if ($h['conteudo_anterior'] !== null): ?>
          <details>
            <summary><?= e($h['titulo_anterior']) ?></summary>
            <div class="conteudo pequeno"><?= e($h['conteudo_anterior']) ?></div>
            <?php if ($pode_editar): ?>
              <form method="post" action="<?= e(url('notas/restaurar')) ?>"
                    onsubmit="return confirm('Restaurar esta versão?');">
                <?= csrf_campo() ?>
                <input type="hidden" name="historico_id" value="<?= e($h['historico_id']) ?>">
                <button class="botao secundario" type="submit">Restaurar esta versão</button>
              </form>
            <?php endif; ?>
          </details>
        <?php else: ?>
          <span class="nota">—</span>
        <?php endif; ?>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
