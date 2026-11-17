<?php $titulo = 'Cadastro'; ?>
<section class="cartao estreito">
  <h1>Criar conta</h1>
  <form method="post" action="<?= e(url('registrar/enviar')) ?>">
    <?= csrf_campo() ?>
    <label>Nome
      <input type="text" name="nome" maxlength="100" value="<?= e(antigo('nome')) ?>" required autofocus>
    </label>
    <label>E-mail
      <input type="email" name="email" maxlength="150" value="<?= e(antigo('email')) ?>" required>
    </label>
    <label>Senha (mínimo <?= e(config('senha_minima')) ?> caracteres)
      <input type="password" name="senha" required>
    </label>
    <label>Repita a senha
      <input type="password" name="senha2" required>
    </label>
    <button class="botao" type="submit">Cadastrar</button>
  </form>
  <p class="nota">Já tem conta? <a href="<?= e(url('entrar')) ?>">Entrar</a></p>
</section>
