(function () {
  function bindRemove(row) {
    var btn = row.querySelector('.sub-remove');
    if (btn) btn.addEventListener('click', function () { row.remove(); });
  }

  document.querySelectorAll('.related-class-list .sub-row').forEach(bindRemove);

  document.querySelectorAll('.add-related-class-row').forEach(function (btn) {
    var field = btn.closest('.form-field');
    var list = field ? field.querySelector('.related-class-list') : null;
    if (!list) return;
    var classOptions = list.getAttribute('data-related-class-options') || '';

    btn.addEventListener('click', function () {
      var row = document.createElement('div');
      row.className = 'sub-row';
      row.innerHTML =
        '<div class="form-control number-select" data-options="' + classOptions + '">' +
          '<input type="text" placeholder="例）002">' +
          '<span class="caret">▾</span>' +
        '</div>' +
        '<div class="sub-remove">✕</div>';
      list.appendChild(row);
      if (window.bindNumberSelect) window.bindNumberSelect(row.querySelector('.number-select'));
      bindRemove(row);
    });
  });
})();
