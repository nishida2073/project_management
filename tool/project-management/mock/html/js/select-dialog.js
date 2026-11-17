(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function fieldHtml(f, names, value) {
    var label = '<label class="input-dialog-label">' + esc(f.label || '') + '</label>';
    if (!f.select) return label + '<div class="input-dialog-name">' + esc(f.text || '') + '</div>';
    var v = names.indexOf(value) === -1 ? '' : value;
    return label +
      '<div class="form-control js-select" data-options="' + esc(names.join(',')) + '" data-value="' + esc(v) + '">' +
        (v ? esc(v) : '選択してください') + '<span class="caret">▾</span></div>';
  }

  function open(opts) {
    var fields = opts.fields || [];
    var sel0 = null;
    for (var i = 0; i < fields.length; i++) {
      if (fields[i].select) { sel0 = fields[i].select; break; }
    }
    var names = sel0 ? (sel0.options || []) : [];
    var value = sel0 ? (sel0.value || '') : '';
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'overlay';
      overlay.innerHTML =
        '<div class="input-dialog">' +
          '<div class="input-dialog-title">' + esc(opts.title || '') + '</div>' +
          fields.map(function (f) { return fieldHtml(f, names, value); }).join('') +
          '<div class="input-dialog-actions">' +
            '<div class="search-btn sd-cancel">キャンセル</div>' +
            '<div class="btn primary sd-ok">' + esc(opts.okLabel || 'OK') + '</div>' +
          '</div>' +
        '</div>';
      document.body.appendChild(overlay);
      var sel = overlay.querySelector('.js-select');
      if (sel) window.bindJsSelect(sel);

      function close(result) {
        document.removeEventListener('keydown', onKey);
        overlay.remove();
        resolve(result);
      }
      function onKey(e) { if (e.key === 'Escape') close(null); }

      overlay.querySelector('.sd-ok').addEventListener('click', function () {
        var v = sel ? (sel.getAttribute('data-value') || '') : '';
        if (names.indexOf(v) === -1) {
          if (opts.allowEmpty) close('');
          return;
        }
        close(v);
      });
      overlay.querySelector('.sd-cancel').addEventListener('click', function () { close(null); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) close(null); });
      document.addEventListener('keydown', onKey);
    });
  }

  window.SelectDialog = { open: open };
})();
