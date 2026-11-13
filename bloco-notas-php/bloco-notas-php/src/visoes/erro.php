<?php $titulo = 'Erro ' . $codigo; ?>
<section class="cartao estreito">
  <h1>Erro <?= e($codigo) ?></h1>
  <p><?= e($mensagem) ?></p>
  <p><a href="<?= e(url('notas')) ?>">Voltar ao início</a></p>
</section>
