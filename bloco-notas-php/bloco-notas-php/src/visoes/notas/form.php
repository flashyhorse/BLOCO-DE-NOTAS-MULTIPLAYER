<?php
/* Formulário usado para CRIAR e para EDITAR (variável $modo).
   Para adicionar um campo novo: inclua o <input> aqui e leia-o em
   ctrl_notas_criar() / ctrl_notas_atualizar(). */
$editando = $modo === 'editar';
$titulo   = $editando ? 'Editar nota' : 'Nova nota';
$marcados_atuais = antigo('temas', $marcados);   // se houve erro, reaproveita o que foi marcado
?>
<h1><?= e($titulo) ?></h1>

<form class="cartao" method="post"
      action="<?= e(url($editando ? 'notas/atualizar' : 'notas/criar')) ?>">
  <?= csrf_campo() ?>
  <?php if ($editando): ?>
    <input type="hidden" name="id" value="<?= e($nota['id']) ?>">
  <?php endif; ?>

  <label>Título
    <input type="text" name="titulo" maxlength="200" required autofocus
           value="<?= e(antigo('titulo', $nota['titulo'] ?? '')) ?>">
  </label>

  <label>Conteúdo
    <textarea name="conteudo" rows="14"><?= e(antigo('conteudo', $nota['conteudo'] ?? '')) ?></textarea>
  </label>

  <?php if ($e_dono): ?>
    <fieldset>
      <legend>Temas</legend>
      <input type="hidden" name="temas_enviados" value="1">
      <?php if (!$temas): ?>
        <p class="nota">Você ainda não tem temas. <a href="<?= e(url('temas')) ?>">Criar temas</a></p>
      <?php endif; ?>
      <?php foreach ($temas as $t): ?>
        <label class="marca-opcao">
          <input type="checkbox" name="temas[]" value="<?= e($t['id']) ?>"
                 <?= in_array((int) $t['id'], array_map('intval', (array) $marcados_atuais), true) ? 'checked' : '' ?>>
          <?= e($t['nome']) ?>
        </label>
      <?php endforeach; ?>
    </fieldset>
  <?php endif; ?>

  <div class="acoes">
    <button class="botao" type="submit">Salvar</button>
    <a href="<?= e($editando ? url('notas/ver', ['id' => $nota['id']]) : url('notas')) ?>">Cancelar</a>
  </div>
</form>
