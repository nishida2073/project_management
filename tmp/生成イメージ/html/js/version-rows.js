(function () {
  function bindRemove(row) {
    var btn = row.querySelector('.sub-remove');
    if (btn) btn.addEventListener('click', function () { row.remove(); });
  }

  document.querySelectorAll('.version-list .sub-row').forEach(bindRemove);

  document.querySelectorAll('.add-version-row').forEach(function (btn) {
    var field = btn.closest('.form-field');
    var versionList = field ? field.querySelector('.version-list') : null;
    if (!versionList) return;
    var versionOptions = versionList.getAttribute('data-version-options') || '';

    btn.addEventListener('click', function () {
      var row = document.createElement('div');
      row.className = 'sub-grid sub-row';
      row.innerHTML =
        '<div class="form-control number-select" data-options="' + versionOptions + '">' +
          '<input type="text" inputmode="decimal" value="1.0">' +
          '<span class="caret">▾</span>' +
        '</div>' +
        '<input type="text" class="form-control" placeholder="例）https://example.com/docs/v1.0">' +
        '<div class="sub-remove">✕</div>';
      versionList.appendChild(row);
      if (window.bindNumberSelect) window.bindNumberSelect(row.querySelector('.number-select'));
      bindRemove(row);
    });
  });
})();
