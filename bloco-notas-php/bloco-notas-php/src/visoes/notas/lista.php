<?php $titulo = 'Notas'; ?>
<div class="barra">
  <h1>Notas</h1>
  <a class="botao" href="<?= e(url('notas/nova')) ?>">Nova nota</a>
</div>

<!-- Busca (RF-09) e filtro por tema (RF-08). É um formulário GET: vira /?r=notas&busca=...&tema=... -->
<form class="busca" method="get" action="/">
  <input type="hidden" name="r" value="notas">
  <input type="search" name="busca" value="<?= e($busca) ?>" placeholder="Buscar no título ou conteúdo">
  <select name="tema" aria-label="Filtrar por tema">
    <option value="">Todos os temas</option>
    <?php foreach ($temas as $t): ?>
      <option value="<?= e($t['id']) ?>" <?= (int) $tema_id === (int) $t['id'] ? 'selected' : '' ?>>
        <?= e($t['nome']) ?> (<?= e($t['total_notas']) ?>)
      </option>
    <?php endforeach; ?>
  </select>
  <button class="botao" type="submit">Filtrar</button>
  <?php if ($busca !== '' || $tema_id): ?>
    <a href="<?= e(url('notas')) ?>">Limpar</a>
  <?php endif; ?>
</form>

<?php if (!$notas): ?>
  <p class="vazio">Nenhuma nota encontrada.</p>
<?php else: ?>
  <div class="tabela-rolagem">
  <table>
    <thead>
      <tr><th>Título</th><th>Dono</th><th>Seu acesso</th><th>Atualizada em</th></tr>
    </thead>
    <tbody>
      <?php foreach ($notas as $n): ?>
        <tr>
          <td><a href="<?= e(url('notas/ver', ['id' => $n['id']])) ?>"><?= e($n['titulo']) ?></a></td>
          <td><?= e($n['dono_nome']) ?></td>
          <td><span class="selo selo-<?= e($n['permissao']) ?>"><?= e($n['permissao']) ?></span></td>
          <td><?= e(fdata($n['atualizado_em'])) ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
  </div>
<?php endif; ?>
