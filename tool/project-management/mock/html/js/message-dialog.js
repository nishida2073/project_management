(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function show(message, onClose) {
    var overlay = document.createElement('div');
    overlay.className = 'overlay';
    overlay.innerHTML =
      '<div class="input-dialog">' +
        '<div class="message-dialog-text">' + esc(message) + '</div>' +
        '<div class="input-dialog-actions">' +
          '<div class="btn primary message-dialog-ok">OK</div>' +
        '</div>' +
      '</div>';
    document.body.appendChild(overlay);

    function close() {
      document.removeEventListener('keydown', onKey);
      overlay.remove();
      if (onClose) onClose();
    }
    function onKey(e) {
      if (e.key === 'Escape' || e.key === 'Enter') close();
    }
    overlay.querySelector('.message-dialog-ok').addEventListener('click', close);
    overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });
    document.addEventListener('keydown', onKey);
    overlay.querySelector('.message-dialog-ok').focus();
  }

  function required(names) {
    show(['必須項目を入力してください'].concat(names.map(function (n) { return '・' + n; })).join(String.fromCharCode(10)));
  }

  function confirm(message) {
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'overlay';
      overlay.innerHTML =
        '<div class="input-dialog">' +
          '<div class="message-dialog-text">' + esc(message) + '</div>' +
          '<div class="input-dialog-actions">' +
            '<div class="search-btn message-dialog-cancel">キャンセル</div>' +
            '<div class="btn primary message-dialog-ok">OK</div>' +
          '</div>' +
        '</div>';
      document.body.appendChild(overlay);

      function finish(value) {
        document.removeEventListener('keydown', onKey);
        overlay.remove();
        resolve(value);
      }
      function onKey(e) {
        if (e.key === 'Escape') finish(false);
        if (e.key === 'Enter') finish(true);
      }
      overlay.querySelector('.message-dialog-ok').addEventListener('click', function () { finish(true); });
      overlay.querySelector('.message-dialog-cancel').addEventListener('click', function () { finish(false); });
      overlay.addEventListener('click', function (e) { if (e.target === overlay) finish(false); });
      document.addEventListener('keydown', onKey);
      overlay.querySelector('.message-dialog-ok').focus();
    });
  }

  window.MessageDialog = { show: show, required: required, confirm: confirm };
})();
