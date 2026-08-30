(function () {
  function bindRemove(row) {
    var btn = row.querySelector('.sub-remove');
    if (btn) btn.addEventListener('click', function () { row.remove(); });
  }

  document.querySelectorAll('.sub-list .sub-row').forEach(bindRemove);

  document.querySelectorAll('.add-row').forEach(function (btn) {
    var field = btn.closest('.form-field');
    var subList = field ? field.querySelector('.sub-list') : null;
    if (!subList) return;
    var vendorOptions = subList.getAttribute('data-vendor-options') || '';

    btn.addEventListener('click', function () {
      var row = document.createElement('div');
      row.className = 'sub-grid sub-row';
      row.innerHTML =
        '<div class="form-control js-select" data-options="' + vendorOptions + '">選択してください<span class="caret">▾</span></div>' +
        '<input type="text" class="form-control" placeholder="例）田中 誠">' +
        '<div class="sub-remove">✕</div>';
      subList.appendChild(row);
      if (window.bindJsSelect) window.bindJsSelect(row.querySelector('.js-select'));
      bindRemove(row);
    });
  });
})();
