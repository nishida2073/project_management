(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function open(opts) {
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'overlay';
      overlay.innerHTML =
        '<div class="input-dialog">' +
          '<div class="input-dialog-title">' + esc(opts.title || '入力') + '</div>' +
          (opts.label ? '<label class="input-dialog-label">' + esc(opts.label) + '</label>' : '') +
          '<input type="text" class="form-control" placeholder="' + esc(opts.placeholder || '') + '">' +
          '<div class="input-dialog-error"></div>' +
          '<div class="input-dialog-actions">' +
            '<div class="search-btn input-dialog-cancel">キャンセル</div>' +
            '<div class="btn primary input-dialog-ok">' + esc(opts.okLabel || '追加') + '</div>' +
          '</div>' +
        '</div>';
      document.body.appendChild(overlay);

      var input = overlay.querySelector('input');
      var errorEl = overlay.querySelector('.input-dialog-error');

      function close(value) {
        document.removeEventListener('keydown', onKey);
        overlay.remove();
        resolve(value);
      }

      function submit() {
        var value = input.value.trim();
        var error = opts.validate ? opts.validate(value) : '';
        if (error) {
          errorEl.textContent = error;
          input.focus();
          return;
        }
        close(value);
      }

      function onKey(e) {
        if (e.key === 'Escape') close(null);
      }

      overlay.querySelector('.input-dialog-ok').addEventListener('click', submit);
      overlay.querySelector('.input-dialog-cancel').addEventListener('click', function () { close(null); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) close(null); });
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') submit(); });
      document.addEventListener('keydown', onKey);
      input.focus();
    });
  }

  window.InputDialog = { open: open };
})();
