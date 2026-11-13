<?php $titulo = 'Entrar'; ?>
<section class="cartao estreito">
  <h1>Entrar</h1>
  <form method="post" action="<?= e(url('entrar/enviar')) ?>">
    <?= csrf_campo() ?>
    <label>E-mail
      <input type="email" name="email" value="<?= e(antigo('email')) ?>" required autofocus>
    </label>
    <label>Senha
      <input type="password" name="senha" required>
    </label>
    <button class="botao" type="submit">Entrar</button>
  </form>
  <p class="nota">Ainda não tem conta? <a href="<?= e(url('registrar')) ?>">Cadastre-se</a></p>
</section>
