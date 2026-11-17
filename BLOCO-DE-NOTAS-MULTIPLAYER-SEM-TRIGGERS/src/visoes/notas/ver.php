<?php
$titulo     = $nota['titulo'];
$e_dono     = $nota['permissao'] === 'dono';
$pode_editar = in_array($nota['permissao'], ['dono', 'edicao'], true);
?>
<div class="barra">
  <h1><?= e($nota['titulo']) ?></h1>
  <div class="acoes">
    <?php if ($pode_editar): ?>
      <a class="botao" href="<?= e(url('notas/editar', ['id' => $nota['id']])) ?>">Editar</a>
    <?php endif; ?>
    <a class="botao secundario" href="<?= e(url('notas/historico', ['id' => $nota['id']])) ?>">Histórico</a>
    <?php if ($e_dono): ?>
      <form method="post" action="<?= e(url('notas/excluir')) ?>"
            onsubmit="return confirm('Excluir esta nota?');">
        <?= csrf_campo() ?>
        <input type="hidden" name="id" value="<?= e($nota['id']) ?>">
        <button class="botao perigo" type="submit">Excluir</button>
      </form>
    <?php endif; ?>
  </div>
</div>

<p class="meta">
  Dono: <?= e($nota['dono_nome']) ?> ·
  Criada em <?= e(fdata($nota['criado_em'])) ?> ·
  Atualizada em <?= e(fdata($nota['atualizado_em'])) ?> ·
  Seu acesso: <span class="selo selo-<?= e($nota['permissao']) ?>"><?= e($nota['permissao']) ?></span>
</p>

<?php if ($temas_da_nota): ?>
  <p class="temas">
    <?php foreach ($temas_da_nota as $t): ?>
      <a class="etiqueta" href="<?= e(url('notas', ['tema' => $t['id']])) ?>"><?= e($t['nome']) ?></a>
    <?php endforeach; ?>
  </p>
<?php endif; ?>

<article class="cartao conteudo"><?= e($nota['conteudo']) ?></article>

<?php if ($e_dono): ?>
  <section class="cartao">
    <h2>Compartilhar</h2>
    <form class="linha" method="post" action="<?= e(url('compartilhar/salvar')) ?>">
      <?= csrf_campo() ?>
      <input type="hidden" name="nota_id" value="<?= e($nota['id']) ?>">
      <input type="email" name="email" placeholder="e-mail do usuário" required
             value="<?= e(antigo('email')) ?>">
      <select name="permissao" aria-label="Permissão">
        <option value="leitura">Somente leitura</option>
        <option value="edicao">Pode editar</option>
      </select>
      <button class="botao" type="submit">Compartilhar</button>
    </form>

    <?php if ($compartilhados): ?>
      <table>
        <thead><tr><th>Usuário</th><th>Permissão</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($compartilhados as $c): ?>
          <tr>
            <td><?= e($c['nome']) ?> <span class="meta">(<?= e($c['email']) ?>)</span></td>
            <td>
              <!-- Trocar a permissão = enviar de novo o mesmo formulário (a regra é "upsert") -->
              <form class="linha" method="post" action="<?= e(url('compartilhar/salvar')) ?>">
                <?= csrf_campo() ?>
                <input type="hidden" name="nota_id" value="<?= e($nota['id']) ?>">
                <input type="hidden" name="email" value="<?= e($c['email']) ?>">
                <select name="permissao" aria-label="Permissão de <?= e($c['nome']) ?>">
                  <option value="leitura" <?= $c['permissao'] === 'leitura' ? 'selected' : '' ?>>Somente leitura</option>
                  <option value="edicao"  <?= $c['permissao'] === 'edicao'  ? 'selected' : '' ?>>Pode editar</option>
                </select>
                <button class="botao secundario" type="submit">Salvar</button>
              </form>
            </td>
            <td>
              <form method="post" action="<?= e(url('compartilhar/remover')) ?>">
                <?= csrf_campo() ?>
                <input type="hidden" name="nota_id" value="<?= e($nota['id']) ?>">
                <input type="hidden" name="usuario_id" value="<?= e($c['usuario_id']) ?>">
                <button class="botao perigo" type="submit">Remover</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    <?php else: ?>
      <p class="nota">Esta nota não está compartilhada com ninguém.</p>
    <?php endif; ?>
  </section>
<?php endif; ?>
