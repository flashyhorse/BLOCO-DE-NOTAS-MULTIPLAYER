<?php $titulo = 'Temas'; ?>
<h1>Meus temas</h1>

<form class="cartao linha" method="post" action="<?= e(url('temas/criar')) ?>">
  <?= csrf_campo() ?>
  <input type="text" name="nome" maxlength="80" placeholder="Novo tema" required
         value="<?= e(antigo('nome')) ?>">
  <button class="botao" type="submit">Criar tema</button>
</form>

<?php if (!$temas): ?>
  <p class="vazio">Você ainda não tem temas.</p>
<?php else: ?>
  <div class="tabela-rolagem">
  <table>
    <thead><tr><th>Tema</th><th>Notas</th><th>Renomear</th><th>Excluir</th></tr></thead>
    <tbody>
    <?php foreach ($temas as $t): ?>
      <tr>
        <td><a href="<?= e(url('notas', ['tema' => $t['id']])) ?>"><?= e($t['nome']) ?></a></td>
        <td><?= e($t['total_notas']) ?></td>
        <td>
          <form class="linha" method="post" action="<?= e(url('temas/renomear')) ?>">
            <?= csrf_campo() ?>
            <input type="hidden" name="id" value="<?= e($t['id']) ?>">
            <input type="text" name="nome" maxlength="80" value="<?= e($t['nome']) ?>" required
                   aria-label="Novo nome do tema <?= e($t['nome']) ?>">
            <button class="botao secundario" type="submit">Salvar</button>
          </form>
        </td>
        <td>
          <form class="linha" method="post" action="<?= e(url('temas/excluir')) ?>">
            <?= csrf_campo() ?>
            <input type="hidden" name="id" value="<?= e($t['id']) ?>">
            <?php if ((int) $t['total_notas'] > 0): ?>
              <!-- RN-07: tema com notas só é excluído com confirmação -->
              <label class="marca-opcao"><input type="checkbox" name="confirmar" value="1" required>
                Confirmo (as notas ficam sem este tema)</label>
            <?php endif; ?>
            <button class="botao perigo" type="submit">Excluir</button>
          </form>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  </div>
<?php endif; ?>
