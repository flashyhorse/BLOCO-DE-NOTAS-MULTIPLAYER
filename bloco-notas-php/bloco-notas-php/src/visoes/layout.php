<?php
/* =====================================================================
   LAYOUT - moldura de todas as telas (cabeçalho, menu, mensagens)
   Recebe: $conteudo (HTML da tela) e, opcionalmente, $titulo.
   ===================================================================== */
$u = usuario_logado();
$titulo_pagina = isset($titulo) ? $titulo . ' – ' . config('app_nome') : config('app_nome');
?>
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= e($titulo_pagina) ?></title>
  <link rel="stylesheet" href="/css/estilo.css">
</head>
<body>
<header class="topo">
  <a class="marca" href="<?= e(url('notas')) ?>"><?= e(config('app_nome')) ?></a>
  <?php if ($u): ?>
    <nav>
      <a href="<?= e(url('notas')) ?>">Notas</a>
      <a href="<?= e(url('temas')) ?>">Temas</a>
      <?php if (($u['perfil'] ?? '') === 'administrador'): ?>
        <a href="<?= e(url('admin/usuarios')) ?>">Administração</a>
      <?php endif; ?>
    </nav>
    <form class="sessao" method="post" action="<?= e(url('sair')) ?>">
      <?= csrf_campo() ?>
      <span><?= e($u['nome']) ?> (<?= e($u['perfil']) ?>)</span>
      <button class="link" type="submit">Sair</button>
    </form>
  <?php endif; ?>
</header>

<main>
  <?php foreach (flashes() as [$tipo, $mensagem]): ?>
    <div class="aviso aviso-<?= e($tipo) ?>" role="status"><?= e($mensagem) ?></div>
  <?php endforeach; ?>

  <?= $conteudo ?>
</main>
</body>
</html>
