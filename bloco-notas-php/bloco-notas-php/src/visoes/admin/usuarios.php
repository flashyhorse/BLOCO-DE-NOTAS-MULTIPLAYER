<?php $titulo = 'Administração'; ?>
<h1>Usuários</h1>
<div class="tabela-rolagem">
<table>
  <thead><tr><th>Nome</th><th>E-mail</th><th>Perfil</th><th>Situação</th><th></th></tr></thead>
  <tbody>
  <?php foreach ($usuarios as $u): ?>
    <tr>
      <td><?= e($u['nome']) ?></td>
      <td><?= e($u['email']) ?></td>
      <td>
        <form class="linha" method="post" action="<?= e(url('admin/usuarios/atualizar')) ?>">
          <?= csrf_campo() ?>
          <input type="hidden" name="usuario_id" value="<?= e($u['id']) ?>">
          <input type="hidden" name="acao" value="perfil">
          <select name="perfil" aria-label="Perfil de <?= e($u['nome']) ?>">
            <?php foreach (PERFIS as $p): ?>
              <option value="<?= e($p) ?>" <?= $u['perfil'] === $p ? 'selected' : '' ?>><?= e($p) ?></option>
            <?php endforeach; ?>
          </select>
          <button class="botao secundario" type="submit">Salvar</button>
        </form>
      </td>
      <td>
        <?php if ($u['bloqueado']): ?>
          <span class="selo selo-bloqueado">bloqueado</span>
        <?php elseif ($u['bloqueio_temporario']): ?>
          <span class="selo selo-bloqueado">bloqueio temporário</span>
        <?php else: ?>
          <span class="selo selo-ativo">ativo</span>
        <?php endif; ?>
      </td>
      <td>
        <form method="post" action="<?= e(url('admin/usuarios/atualizar')) ?>">
          <?= csrf_campo() ?>
          <input type="hidden" name="usuario_id" value="<?= e($u['id']) ?>">
          <?php if ($u['bloqueado'] || $u['bloqueio_temporario']): ?>
            <input type="hidden" name="acao" value="desbloquear">
            <button class="botao secundario" type="submit">Desbloquear</button>
          <?php else: ?>
            <input type="hidden" name="acao" value="bloquear">
            <button class="botao perigo" type="submit">Bloquear</button>
          <?php endif; ?>
        </form>
      </td>
    </tr>
  <?php endforeach; ?>
  </tbody>
</table>
</div>
